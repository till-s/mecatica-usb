// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Trivial driver (not efficient) for Usb2 demo ECM device;
 * ** THIS IS NOT AN USB DRIVER**
 * this driver serves the FIFOs implemented on the target
 * Zynq device. It must be cross-compiled and used on the
 * example target platform.
 *
 * Copyright (C) 2023, Till Straumann
 *
 * Note that this file is released under the GPL to be
 * compatible with the linux kernel.
 *
 * https://www.gnu.org/licenses/gpl-3.0-standalone.html
 */

/*
 * Demo driver for the Usb2Example ECM ethernet device.
 *
 * THIS IS NOT A USB DRIVER.
 *
 * This driver implements a 'peer' device to the USB-ECM
 * device. The latter is accessed by the host via USB;
 * this device implements a network device on the target
 * (zynq) system and accesses the ECM device's fifos from
 * the AXI bus.
 *
 *   Target (zynq)                                 Host
 *   Linux                   firmware              Linux
 * 
 *    this driver <- AXI ->  Usb2Example <- USB -> ECM USB driver
 */

/* #define DEBUG */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/errno.h>
#include <linux/device.h>
#include <linux/platform_device.h>
#include <linux/etherdevice.h>
#include <linux/spinlock.h>
#include <linux/skbuff.h>

MODULE_LICENSE("GPL");
MODULE_ALIAS("platform:exFifoEth");

#define MYNAME "usbExampleFifoEth"
#define MYMTU  1536

#define MAPSZ 0x1000

#define INP_FIFO_SIZE

#define IRQ_STAT_REG       0x50
#define IRQ_ENBL_REG       0x90
#define INP_FIFO_FILL_REG  0x40
#define OUT_FIFO_FILL_REG  0x44
#define FIFO_CTL_0_REG     0x80
#define CARRIER_ON         (1<<31)
#define FIFO_CTL_1_REG     0x84
#define FIFO_REG           0xc0

#define RX_FIFO_EMPTY (1<<8)
#define RX_FIFO_LAST  (1<<9)
#define TX_FIFO_LAST  (1<<9)

#define RX_FIFO_IRQ  (1<<0)
#define TX_FIFO_IRQ  (1<<1)

#define FW_ECM   1
#define FW_NCM   2

struct drv_info {
	struct net_device       *ndev;
	void __iomem            *base;
	struct task_struct      *kworker_task;
    struct kthread_worker    kworker;
    struct kthread_work      rx_work;
    spinlock_t               lock;
    unsigned                 txFifoSize;
    unsigned                 rxFifoSize;
	int                      fwType;
};

/* Fwd declarations */
static int ndev_open(struct net_device *ndev);
static int ndev_close(struct net_device *ndev);
static netdev_tx_t ndev_hard_start_xmit(struct sk_buff *skb, struct net_device *ndev);
static void ndev_tx_timeout(struct net_device *ndev, unsigned int txqueue);

static const struct net_device_ops my_ndev_ops = {
	.ndo_open            = ndev_open,
	.ndo_stop            = ndev_close,
	.ndo_start_xmit      = ndev_hard_start_xmit,
	.ndo_tx_timeout      = ndev_tx_timeout,
	.ndo_set_mac_address = eth_mac_addr,
	.ndo_validate_addr   = eth_validate_addr,
};

static void
disable_irqs(struct drv_info *me, u32 msk)
{
unsigned long flags;
u32           val;
	msk &= (RX_FIFO_IRQ | TX_FIFO_IRQ);
	spin_lock_irqsave( &me->lock, flags );
		val = ioread32( me->base + IRQ_ENBL_REG );
		val &= ~msk;
		iowrite32( val, me->base + IRQ_ENBL_REG );
	spin_unlock_irqrestore( &me->lock, flags );
}

static void
enable_irqs(struct drv_info *me, u32 msk)
{
unsigned long flags;
u32           val;
	msk &= (RX_FIFO_IRQ | TX_FIFO_IRQ);
	spin_lock_irqsave( &me->lock, flags );
		val = ioread32( me->base + IRQ_ENBL_REG );
		val |= msk;
		iowrite32( val, me->base + IRQ_ENBL_REG );
	spin_unlock_irqrestore( &me->lock, flags );
}

static void set_carrier(struct drv_info *me, int on)
{
unsigned long flags;
u32           val;
	spin_lock_irqsave( &me->lock, flags );
		val = ioread32( me->base + FIFO_CTL_0_REG );
		if ( on ) {
			val |= CARRIER_ON;
		} else {
			val &= ~CARRIER_ON;
		}
		iowrite32( val, me->base + FIFO_CTL_0_REG );
	spin_unlock_irqrestore( &me->lock, flags );
}

static unsigned
txFifoSize(struct drv_info *me)
{
	return 1 << ( ( ioread32( me->base + INP_FIFO_FILL_REG ) >> 28 ) & 0xf );
}

static int
fwType(struct drv_info *me)
{
	return ( ( ioread32( me->base + INP_FIFO_FILL_REG ) >> 21 ) & 0x7 );
}

static unsigned
rxFifoSize(struct drv_info *me)
{
	return 1 << ( ( ioread32( me->base + INP_FIFO_FILL_REG ) >> 24 ) & 0xf );
}


static int
rxFramesAvailable(struct drv_info *me)
{
	return ( ioread32( me->base + OUT_FIFO_FILL_REG ) >> 16 ) & 0xffff;
}

/*
static int
rxBytesAvailable(struct drv_info *me)
{
	return ioread32( me->base + OUT_FIFO_FILL_REG ) & 0xffff;
}
*/

static int
txSpaceAvailable(struct drv_info *me)
{
	if ( FW_ECM == me->fwType ) {
		return me->txFifoSize - ( ioread32( me->base + INP_FIFO_FILL_REG ) & 0xffff );
	} else {
		return (s16)(ioread32( me->base + INP_FIFO_FILL_REG ) & 0xffff);
	}
}

static inline u32
rxFifoPop(struct drv_info *me)
{
u32 d = ioread32( me->base + FIFO_REG );
	BUG_ON( !! (d & RX_FIFO_EMPTY) );
	return d;
}

static inline void
rxFifoDrain(struct drv_info *me)
{
	while ( ! (RX_FIFO_EMPTY & ioread32( me->base + FIFO_REG ) ) )
		/* nothing else */;
}

/* assumes enough space is available! */
static inline void
txFifoPush(struct drv_info *me, struct sk_buff *skb)
{
int  i;
u8  *p = (u8*)skb->data;

	if ( skb->len == 0 ) {
		return;
	}
	for ( i = 0; i < skb->len - 1 ; i++ ) {
		iowrite32( (u32)(*p), me->base + FIFO_REG );
		p++;
	}
	/* EOP marker */
	iowrite32( (u32)TX_FIFO_LAST | (u32)(*p), me->base + FIFO_REG );
}

static int
ndev_open(struct net_device *ndev)
{
	struct drv_info     *me = netdev_priv( ndev );

	enable_irqs( me, RX_FIFO_IRQ | TX_FIFO_IRQ );

	netif_start_queue( ndev );
	set_carrier( me, 1 );
	return 0;
}

static int
ndev_close(struct net_device *ndev)
{
	struct drv_info     *me = netdev_priv( ndev );

	set_carrier( me, 0 );

	netif_stop_queue( ndev );
	netif_carrier_off( ndev );

	rxFifoDrain( me );

	return 0;
}

static netdev_tx_t
ndev_hard_start_xmit(struct sk_buff *skb, struct net_device *ndev)
{
	struct drv_info     *me = netdev_priv( ndev );
	int                  avail;


	avail = txSpaceAvailable( me );
	netdev_dbg(ndev, "ex_fifo hard_start_xmit entering (space %d).\n", avail);

	if ( unlikely( skb->len ) > avail ) {
		ndev->stats.tx_errors++;
		ndev->stats.tx_dropped++;
		dev_kfree_skb_any( skb );
		return NETDEV_TX_OK;
	}

	txFifoPush( me, skb );

    ndev->stats.tx_packets++;
    ndev->stats.tx_bytes += skb->len;

	netif_trans_update( ndev );
	dev_consume_skb_any( skb );

	if ( txSpaceAvailable( me ) < (MYMTU + 1) ) {
		netif_stop_queue( ndev );
		enable_irqs( me, TX_FIFO_IRQ );
	} else {
		netif_wake_queue( ndev );
	}

	return NETDEV_TX_OK;
}

static void
ndev_tx_timeout(struct net_device *ndev, unsigned int txqueue)
{
	netdev_err( ndev, "ndev_timeout -- should not happen\n" );
	netif_trans_update( ndev );
	netif_wake_queue( ndev );
}

static irqreturn_t ex_fifo_eth_drv_irq(int irq, void *closure)
{
	struct net_device *ndev = (struct net_device*)closure;
	struct drv_info     *me = netdev_priv( ndev );
	irqreturn_t        rval = IRQ_NONE;
	u32                pend = ioread32( me->base + IRQ_STAT_REG );
	u32                mask = pend & (RX_FIFO_IRQ | TX_FIFO_IRQ);

	/* disable irqs */
	disable_irqs( me, mask );

	if ( (pend & RX_FIFO_IRQ) ) {
		kthread_queue_work( & me->kworker, &me->rx_work );
		rval  = IRQ_HANDLED;
	}

	if ( (pend & TX_FIFO_IRQ) ) {
		netif_wake_queue( ndev );
		rval  = IRQ_HANDLED;
	}

	return rval;
}

static void rx_work_fn(struct kthread_work *w)
{
	struct drv_info   *me   = container_of( w, struct drv_info, rx_work );
	struct net_device *ndev = me->ndev;
	struct sk_buff    *skb;
	u8                *p;
	unsigned           len;
	int                i;
	u32                d;

	while ( rxFramesAvailable( me ) > 0 ) {
		/* we don't have accurate length information; just best guess */
/*		if ( (len = rxBytesAvailable( me )) > MYMTU ) */ {
			len = MYMTU;
		}
		skb = netdev_alloc_skb( ndev, len );
		if ( unlikely( skb == NULL || skb_tailroom( skb ) < len ) ) {
			if ( skb == NULL ) {
				netdev_err( ndev, "No memory, RX packet dropped.\n");
			} else {
				netdev_err( ndev, "Not enough tailroom (?!), RX packet dropped.\n");
				dev_kfree_skb_any( skb );
			}
			while ( rxFramesAvailable( me ) > 0 ) {
				while ( ! (rxFifoPop( me ) & RX_FIFO_LAST) )
					/* nothing else to do */;
				ndev->stats.rx_dropped++;
			}
		} else {
			p = skb->data;
			i = 0;
			while ( i < len ) {
				d = rxFifoPop( me );
				*p = (u8)(d & 0xff);
				i++;
				p++;
				if ( !! (d & RX_FIFO_LAST)  ) {
					break;
				}
			}
			if ( i < len ) {
				len = i;
				skb_put( skb, len ); 
				skb->protocol = eth_type_trans( skb, ndev );
				netif_rx( skb );
				ndev->stats.rx_packets++;
				ndev->stats.rx_bytes += len;
			} else {
				netdev_err( ndev, "Not enough room (?!), RX packet dropped.\n");
				while ( ! (rxFifoPop( me ) & RX_FIFO_LAST ) )
					/* nothing else to do */;
				ndev->stats.rx_dropped++;
				dev_kfree_skb_any( skb );
			}
		}
	}

	enable_irqs( me, RX_FIFO_IRQ );
}


static int ex_fifo_eth_drv_probe(struct platform_device *pdev)
{
	struct net_device *ndev = 0;
	struct resource   *res  = 0;
	void   __iomem    *addr = 0;
	int                rval = -ENODEV;
	int                irq  = -1;
	struct drv_info   *me;

	if ( ! (res = platform_get_resource( pdev, IORESOURCE_MEM, 0 )) ) {
		goto bail;
	}

	if ( ! request_mem_region( res->start, MAPSZ, MYNAME ) ) {
		rval = -EBUSY;
		res  = 0;
		goto bail;
	}

	if ( ! (ndev = alloc_etherdev( sizeof( struct drv_info ) ) ) ) {
		rval = -ENOMEM;
		goto bail;
	}

	SET_NETDEV_DEV( ndev, &pdev->dev );
	me = netdev_priv( ndev );
	me->ndev  = ndev;
	ndev->irq = -1;

	ndev->netdev_ops = &my_ndev_ops;
	ndev->dma        = (unsigned char) -1;
	me->kworker_task = 0;

	/* pick a random mac address */
	eth_hw_addr_random( ndev );

	netdev_dbg(ndev, "ex_fifo probe\n");

	if ( (irq = platform_get_irq( pdev , 0 )) < 0 ) {
		rval = irq;
		netdev_dbg(ndev, "ex_fifo probe\n");
		goto bail;
	}


	if ( ! (addr = ioremap( res->start, MAPSZ )) ) {
		rval = -ENOMEM;
		netdev_err(ndev, "ex_fifo unable to map IO memory\n");
		goto bail;
	}

	me->base = addr;

    me->fwType = fwType( me );
	if ( ( FW_ECM != me->fwType ) && ( FW_NCM != me->fwType ) ) {
		netdev_err(ndev, "ex_fifo unknown firmware: 0x%x\n", me->fwType );
		goto bail;
	}

	disable_irqs( me, (RX_FIFO_IRQ | TX_FIFO_IRQ | RST_CHG_IRQ) );

	if ( ( rval = request_irq( irq, ex_fifo_eth_drv_irq, IRQF_SHARED, ndev->name, ndev ) ) ) {
		netdev_err(ndev, "ex_fifo unable to request IRQ\n");
		goto bail;
	}
	ndev->irq = irq;

	me->txFifoSize = txFifoSize( me );
	me->rxFifoSize = rxFifoSize( me );

	spin_lock_init( &me->lock );

	kthread_init_worker( &me->kworker );
	kthread_init_work( &me->rx_work, rx_work_fn );

	me->kworker_task = kthread_run( kthread_worker_fn, &me->kworker, "usb2exfifoeth" );
	if ( IS_ERR( me->kworker_task ) ) {
		rval             = PTR_ERR( me->kworker_task );
		me->kworker_task = 0;
		netdev_err(ndev, "ex_fifo creating worker task failed.\n");
		goto bail;
	}

	if ( ( rval = register_netdev( ndev ) ) ) {
		netdev_err(ndev, "ex_fifo registering netdev failed.\n");
		goto bail;
	}

	platform_set_drvdata( pdev, ndev );
	me->base        = addr;	
	ndev->base_addr = res->start;

	netdev_dbg(ndev, "ex_fifo probe successful.\n");
	return 0;

bail:
	if ( addr ) {
		iounmap( addr );
	}
	if ( ndev ) {
		if ( me->kworker_task ) {
			kthread_stop( me->kworker_task );
		}
		if ( ndev->irq >= 0 ) {
			free_irq( ndev->irq, ndev );
		}
		free_netdev( ndev );
	}
	if ( res ) {
		release_mem_region( res->start, MAPSZ );
	}
	return rval;
}

static int ex_fifo_eth_drv_remove(struct platform_device *pdev)
{
	struct net_device *ndev = platform_get_drvdata( pdev );
	struct drv_info   *me   = netdev_priv( ndev );
	struct resource   *res  = 0;

	disable_irqs( me, RX_FIFO_IRQ | TX_FIFO_IRQ );
	kthread_stop( me->kworker_task );

	unregister_netdev( ndev );
	free_irq( ndev->irq, ndev );
	iounmap( me->base );

	res = platform_get_resource( pdev, IORESOURCE_MEM, 0 );
	release_mem_region( res->start, MAPSZ );
	free_netdev( ndev );
	return 0;
}

static struct platform_driver ex_fifo_eth_driver = {
	.probe  = ex_fifo_eth_drv_probe,
	.remove = ex_fifo_eth_drv_remove,
	.driver = {
		.name = MYNAME
	}
};

module_platform_driver(ex_fifo_eth_driver);

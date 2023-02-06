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
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/errno.h>
#include <linux/device.h>
#include <linux/platform_device.h>
#include <linux/etherdevice.h>
#include <linux/spinlock.h>

MODULE_LICENSE("GPL");
MODULE_ALIAS("platform:exFifoEth");

#define MYNAME "usbExampleFifoEth"

#define MAPSZ 0x1000

#define IRQ_STAT_REG 0x50
#define IRQ_ENBL_REG 0x90

#define RX_FIFO_IRQ  (1<<0)
#define TX_FIFO_IRQ  (1<<1)

struct drv_info {
	struct net_device       *ndev;
	void __iomem            *base;
	struct task_struct      *kworker_task;
    struct kthread_worker    kworker;
    struct kthread_work      tx_work;
    struct kthread_work      rx_work;
    spinlock_t               lock;
};

static void disable_irqs(struct drv_info *me, u32 msk)
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

static void enable_irqs(struct drv_info *me, u32 msk)
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

static int rxFramesAvailable(struct drv_info *me)
{
	return 0;
}

static int txSpaceAvailable(struct drv_info *me)
{
	return 0;
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
		kthread_queue_work( & me->kworker, &me->tx_work );
		rval  = IRQ_HANDLED;
	}

	return rval;
}

static void tx_work_fn(struct kthread_work *w)
{
	struct drv_info *me = container_of( w, struct drv_info, tx_work );

	while ( txSpaceAvailable( me ) ) {
	}

	enable_irqs( me, TX_FIFO_IRQ );
}

static void rx_work_fn(struct kthread_work *w)
{
	struct drv_info *me = container_of( w, struct drv_info, rx_work );

	while ( rxFramesAvailable( me ) > 0 ) {
	}

	enable_irqs( me, RX_FIFO_IRQ );
}


static int ex_fifo_eth_drv_probe(struct platform_device *pdev)
{
	struct net_device *ndev = 0;
	struct resource   *res  = 0;
	void   __iomem    *addr = 0;
	int                rval = -ENODEV;
	struct drv_info   *me;

	printk(KERN_INFO "ex_fifo probe\n");

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
	me->ndev = ndev;

	ndev->dma        = (unsigned char) -1;
	me->kworker_task = 0;

	if ( (ndev->irq = platform_get_irq( pdev , 0 )) < 0 ) {
		rval = ndev->irq;
		goto bail;
	}


	if ( ! (addr = ioremap( res->start, MAPSZ )) ) {
		rval = -ENOMEM;
		goto bail;
	}

	if ( ( rval = request_irq( ndev->irq, ex_fifo_eth_drv_irq, IRQF_SHARED, ndev->name, ndev ) ) ) {
		goto bail;
	}

	spin_lock_init( &me->lock );

	kthread_init_worker( &me->kworker );
	kthread_init_work( &me->tx_work, tx_work_fn );
	kthread_init_work( &me->rx_work, rx_work_fn );

	me->kworker_task = kthread_run( kthread_worker_fn, &me->kworker, "usb2exfifoeth" );
	if ( IS_ERR( me->kworker_task ) ) {
		rval             = PTR_ERR( me->kworker_task );
		me->kworker_task = 0;
		goto bail;
	}

	if ( ( rval = register_netdev( ndev ) ) ) {
		goto bail;
	}

	enable_irqs( me, RX_FIFO_IRQ | TX_FIFO_IRQ );

	platform_set_drvdata( pdev, ndev );
	me->base        = addr;	
	ndev->base_addr = res->start;

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

/*
 * Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
 * You may obtain a copy of the license at
 *   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
 * This notice must not be removed.
 */

#include <sys/mman.h>
#include <fcntl.h>
#include <stdio.h>
#include <inttypes.h>
#include <getopt.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>

/* THIS PROGRAM IS TO BE RUN ON THE ZYNQ TARGET; IT DOES *not* USE USB */

/* Trivial program to access the Usb2Example application
 * on the *target* (= Zynq) system.
 * This is not using USB but communicating with the endpoints
 * in the PL via AXI.
 * Cross-compile for ARM-linux.
 * You'll need
 *   - the uio_pdrv_genirq driver on the zynq system
 *   - a device-tree entry that describes the memory 
 *     region used by the example device
 *           0xXXC01000
 *     and the second PL->CPU interrupt (irq(1) if
 *     irq is a std_logic_vector(15 downto 0)).
 *
 * This program can
 *   - read registers of the ULPI PHY (by default just the ID as
 *     an example)
 *   - read/write control registers that control FIFO behavior
 *   - read from the CDC-ACM fifo and dump contents.
 */

typedef struct ExampleDev {
	int               fd;
	volatile uint8_t *baddr;
	size_t            mapsz;
    uint32_t          ctrl_orig;
} ExampleDev;

#define ULPI_REG_BASE    0x00000000
#define ULPI_ID_REG_OFF  0x00000000

#define STATUS_REG_BASE  0x00000040
#define CTRL_REG_BASE    0x00000080
#define ACM_FIFO_BASE    0x000000c0

#define ACM_FIFO_CTRL    0x00000000
/* Enable 'blast' mode; incoming traffic is dumped, output
 * is filled by firmware as fast as it can be consumed; for
 * throughput testing (from USB)
 */
#define ACM_FIFO_CTRL_BLAST        (1<<27)
/* Disable loopback mode (by default traffic is looped
 * back in firmware)
 */
#define ACM_FIFO_CTRL_LOOP_DIS     (1<<28)
/* Minfill level before data is handed to USB;
 * increases efficiency with slower writers
 */
#define ACM_FIFO_CTRL_MINFILL_MSK  0x7ff

/*
 * Timer (in 60Mhz cycles); fifo is sent to USB
 * if no new data have been written in this time
 * (relevant in combination with MINFILL)
 */
#define ACM_FIFO_TIMER   0x00000004

#define FIFO_EMPTY (1<<8)
#define LINE_BREAK (1<<9)

static inline uint8_t
read_ulpi_reg(ExampleDev *pdev, unsigned reg)
{
	return *(volatile uint8_t*)(pdev->baddr + ULPI_REG_BASE + reg);
}

static inline uint32_t
read_status_reg(ExampleDev *pdev, unsigned reg)
{
	return *(volatile uint32_t*)(pdev->baddr + STATUS_REG_BASE + reg);
}

static inline uint32_t
read_ctrl_reg(ExampleDev *pdev, unsigned reg)
{
	return *(volatile uint32_t*)(pdev->baddr + CTRL_REG_BASE + reg);
}

static inline void
write_ctrl_reg(ExampleDev *pdev, unsigned reg, uint32_t v)
{
	*(volatile uint32_t*)(pdev->baddr + CTRL_REG_BASE + reg) = v;
}


static inline uint32_t
read_acm_fifo(ExampleDev *pdev)
{
uint32_t v = *(volatile uint32_t*)(pdev->baddr + ACM_FIFO_BASE);
	return v;
}

static inline void
write_acm_fifo(ExampleDev *pdev, uint8_t val)
{
uint32_t v = (uint32_t)val;
	*(volatile uint32_t*)(pdev->baddr + ACM_FIFO_BASE) = v;
}

static int
irqEnable(ExampleDev *pdev)
{
uint32_t val = 1;
	if ( write( pdev->fd, &val, sizeof(val) ) != sizeof(val) ) {
		perror("writing to UIO device");
		return -1;
	}
	return 0;
}

static int
irqWait(ExampleDev *pdev)
{
uint32_t val;
	if ( irqEnable( pdev ) ) {
		return -1;
	}
	if ( read( pdev->fd, &val, sizeof(val) ) != sizeof(val) ) {
		perror("reading from UIO device");
		return -1;
	}
	return 0;
}

static ExampleDev *
devOpen(const char *name)
{
ExampleDev   *pdev   = 0;
void         *maddr  = MAP_FAILED;
int           fd     = -1;
int           sz     = sysconf(_SC_PAGE_SIZE);

	if  ( (fd = open( name, O_RDWR ) ) < 0 ) {
		perror("opening device");
		goto bail;
	}

	maddr = mmap( 0, sz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0 );
	if ( MAP_FAILED == maddr ){
		perror("unable to map device memory");
		goto bail;
	}

	if ( ! (pdev = malloc( sizeof( *pdev ))) ) {
		perror("no memory");
		goto bail;
	}

	pdev->baddr       = (volatile uint8_t*) maddr;
	pdev->mapsz       = sz;
	pdev->fd          = fd;

	pdev->ctrl_orig   = read_ctrl_reg( pdev, ACM_FIFO_CTRL );

	return pdev;

bail:
	if ( MAP_FAILED != maddr ) {
		munmap( maddr, sz );
	}
	if ( fd >= 0 ) {
		close( fd );
	}
	free( pdev );
	return 0;
}

static void
devClose(ExampleDev *pdev)
{
	if ( pdev ) {
		write_ctrl_reg( pdev, ACM_FIFO_CTRL, pdev->ctrl_orig );
		munmap( (void*)pdev->baddr, pdev->mapsz );
		close( pdev->fd );
		free( pdev );
	}
}

#define HEX_DUMP 2

static void
usage(const char *nm)
{
	printf("usage: %s [-d <uio-device>] [-hI] [-F<mode>]\n", nm);
	printf("  Simple program to access features of the USB2Example\n");
	printf("  design on the *target* Zynq system.\n");
	printf("  The idea is that you have a host connected to USB\n");
	printf("  and on the host you use e.g., the cdc-acm driver.\n");
	printf("  %s can then be used on the target to receive and print\n", nm);
	printf("  data that are sent by the host.\n");
	printf("\n");
	printf("Options:\n");
	printf("  -h                : Print this message\n");
	printf("  -I                : Print ULPI PHY vendor ID\n");
	printf("  -F <mode>         : Read from the ACM endpoint FIFO\n");
	printf("                      and dump to stdout. The <mode> may\n");
	printf("                      be 'ascii' or 'hex'. 'ascii' is most\n");
	printf("                      convenient if the host has a terminal\n");
	printf("                      connected to the USB ACM device.\n");
	printf("                      Reading continues until a line break\n");
    printf("                      condition is detected (or the program is\n");
    printf("                      killed.)\n");

}

int
main(int argc, char **argv)
{
int           rv        = 1;
char         *fname     = "/dev/uio0";
ExampleDev   *pdev      = 0;
int           dumpFifo  = 0;
int           dumpPhyId = 0;
uint32_t      val;
int           opt, i;
uint32_t      got;
int          *i_p;
int           lineBreak;

	while ( ( opt = getopt( argc, argv, "hF:I" ) ) > 0 ) {
		i_p = 0;
		switch ( opt ) {
			case 'h': usage(argv[0]);         return 0;
			case 'F': i_p = &dumpFifo;        break;
			case 'I': dumpPhyId = 1;          break;
			default:
				fprintf(stderr, "Unsupported option -%c\n", opt);
				goto bail;
		}
		if ( i_p && 1 != sscanf( optarg, "%i", i_p ) ) {
			fprintf( stderr, "Invalid argument for option -%c\n", opt );
			goto bail;
		}
	}

	if ( ! (pdev = devOpen( fname ) ) ) {
		goto bail;
	}

	if ( dumpPhyId ) {
		printf("Ulpi PHY ID: ");
		for ( i = 0; i < 4; i ++ ) {
			printf("%02" PRIx8, read_ulpi_reg( pdev, ULPI_ID_REG_OFF + i ));
		}
		printf("\n");
	}

	if ( dumpFifo ) {
		val = read_ctrl_reg( pdev, ACM_FIFO_CTRL );
		val |= ACM_FIFO_CTRL_LOOP_DIS;
		write_ctrl_reg( pdev, ACM_FIFO_CTRL, val );

		lineBreak = 0;
		while ( ! lineBreak ) {
			/* show what we've got so far */
			fflush( stdout );

			/* wait for more */
			irqWait( pdev );
			i = 0;
			while ( 1 ) {
				got = read_acm_fifo( pdev );
				if ( (got & LINE_BREAK) ) {
					lineBreak = 1;
				}
				if ( (got & FIFO_EMPTY) ) {
					break;
                }
				if ( HEX_DUMP == dumpFifo ) {
					printf("0x%02x ", got);
					if ( ++i == 16 ) {
						i = 0;
						printf("\n");
					}
				} else {
					printf("%c", got);
				}
			}
		}
	}

	rv = 0;
bail:
	devClose( pdev );
	return rv;
}

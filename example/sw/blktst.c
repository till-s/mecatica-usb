/*
 * Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
 * You may obtain a copy of the license at
 *   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
 * This notice must not be removed.
 */

#include <stdio.h>
#include <libusb-1.0/libusb.h>
#include <getopt.h>
#include <string.h>
#include <time.h>
#include <errno.h>

#define INTF_NUMBER 1

#define BUFSZ (16*65536)

#define _STR_(x) # x
#define _STR(x) _STR_(x)

static void usage(const char *nm, int lvl)
{
	printf("usage: %s [-l <bufsz>] [-w] [-h] %s\n", nm, (lvl > 0 ? "[-f <val>] [-1 <off>] [-H <len>]" : "") );
    printf("Testing USB DCDAcm Example Using libusb\n");
    printf("  -h           : this message (repeated -h increases verbosity of help)\n");
    printf("  -l <bufsz>   : set buffer size (max = default = %s = %d);\n", _STR(BUFSZ), BUFSZ);
    printf("                 a larger buffer results in more parallel asynchronous\n");
    printf("                 operations which is more efficient.\n");
    printf("  -w           : write to the USB device (default is reading)\n");
    if ( lvl > 0 ) {
    printf("  -f <val>     : fill the buffer with <val> (default is a repeating\n");
    printf("                 pattern 0x00, 0x01, 0x02, .., 0xff). Due to bit-stuffing\n");
    printf("                 the transferred value(s) impact throughput; all-0xff\n");
    printf("                 produces a maximum of stuffed bits.\n");
    printf("  -1 <off>     : fill with all-zeros but set the byte at offset <off> to 0xff.\n");
    printf("                 (For specialized testing/debugging.)\n");
    printf("  -H <len>     : fill the first <len> bytes with 0xff, the rest with 0x00\n");
    printf("                 (For specialized testing/debugging.)\n");
	}
}

int
main(int argc, char **argv)
{
libusb_device_handle                            *devh  = 0;
libusb_context                                  *ctx   = 0;
int                                              rv    = 1;
int                                              intf  = -1;
int                                              st;
struct libusb_config_descriptor                 *cfg   = 0;
const struct libusb_endpoint_descriptor         *e     = 0;
int                                              rendp = -1;
int                                              wendp = -1;
int                                              xendp;
int                                              i, got, tot;
unsigned char                                    buf[BUFSZ];
int                                              opt;
int                                              len = sizeof(buf);
int                                             *i_p;
int                                              fill = -1;
int                                              oneo = -1;
int                                              head = -1;
int                                              wr   =  0;
struct timespec                                  then, now;
double                                           diff, rate;
int                                              help = -1;

	while ( (opt = getopt(argc, argv, "l:f:1:H:wh")) > 0 ) {
		i_p = 0;
		switch (opt)  {
            case 'h':  help++;        break;
			case 'H':  i_p = &head;   break;
			case '1':  i_p = &oneo;   break;
			case 'f':  i_p = &fill;   break;
			case 'l':  i_p = &len;    break;
            case 'w':  wr  = 1;       break;
			default:
				fprintf(stderr, "Error: Unknown option -%c\n", opt);
                usage( argv[0], 0 );
				goto bail;
		}
		if ( i_p && 1 != sscanf(optarg, "%i", i_p) ) {
			fprintf(stderr, "Unable to scan option -%c arg\n", opt);
			goto bail;
		}
	}

    if ( help >= 0 ) {
		usage( argv[0], help );
		return 0;
	}

	if ( len < 0 || len > sizeof(buf) ) {
		fprintf(stderr, "Invalid length\n");
		goto bail;
	}

	if ( oneo >= len ) {
		fprintf(stderr, "Invalid oneo\n");
		goto bail;
	}

	if ( head >= len ) {
		fprintf(stderr, "Invalid head\n");
		goto bail;
	}

	if ( oneo >= 0 || head >= 0 ) {
		fill = 0;
	}

	if ( fill >= 0 ) {
		memset( buf, (unsigned char)(fill & 0xff), sizeof(buf) );
	} else {
		for ( i = 0; i < sizeof(buf); i++ ) {
			buf[i] = (unsigned char)(i & 0xff);
		}
	}

	if ( oneo >= 0 ) {
		buf[oneo] = 0xff;
	}

	for ( i = 0; i <= head; i++ ) {
		buf[i] = 0xff;
	}

	st = libusb_init( &ctx );
	if ( st ) {
		fprintf(stderr, "libusb_init: %i\n", st);
		goto bail;
	}

	devh = libusb_open_device_with_vid_pid( ctx, 0x0123, 0xabcd );
	if ( ! devh ) {
		fprintf(stderr, "libusb_open_device_with_vid_pid: not found\n");
		goto bail;
	}

	if ( libusb_set_auto_detach_kernel_driver( devh, 1 ) ) {
		fprintf(stderr, "libusb_set_auto_detach_kernel_driver: failed\n");
		goto bail;
	}

    st = libusb_get_active_config_descriptor( libusb_get_device( devh ), &cfg );
	if ( st ) {
		fprintf(stderr, "libusb_get_active_config_descriptor: %i\n", st);
		goto bail;
	}

	if ( cfg->bNumInterfaces <= INTF_NUMBER ) {
		fprintf(stderr, "unexpected number of interfaces!\n");
		goto bail;
	}

    /* CDC Data */
	if ( cfg->interface[INTF_NUMBER].altsetting[0].bInterfaceClass != 10 ) {
		fprintf(stderr, "unexpected interface class (not CDC Data)\n");
		goto bail;
	}

	st = libusb_claim_interface( devh, INTF_NUMBER );
	if ( st ) {
		fprintf(stderr, "libusb_claim_interface: %i\n", st);
		goto bail;
	}

	e = cfg->interface[INTF_NUMBER].altsetting[0].endpoint;
	for ( i = 0; i < cfg->interface[INTF_NUMBER].altsetting[0].bNumEndpoints; i++, e++ ) {
		if ( LIBUSB_TRANSFER_TYPE_BULK != (LIBUSB_TRANSFER_TYPE_MASK & e->bmAttributes) ) {
			continue;
		}
		if ( LIBUSB_ENDPOINT_DIR_MASK & e->bEndpointAddress ) {
			rendp = e->bEndpointAddress;
		} else {
			wendp = e->bEndpointAddress;
		}
	}

	if ( rendp < 0 || wendp < 0 ) {
		fprintf(stderr, "Unable to find (both) bulk endpoints\n");
		goto bail;
	}

	tot = 0;

    xendp = wr ? wendp : rendp;

    if ( clock_gettime( CLOCK_MONOTONIC, &then ) ) {
		fprintf(stderr, "Unable to read clock/time: %s\n", strerror( errno ) );
		goto bail;
	}

	while ( tot < 100*1024*1024 ) {
		got = len;
		st = libusb_bulk_transfer( devh, xendp, buf, got, &got, 1000 );
		if ( st || 0 == got ) {
			fprintf(stderr, "Bulk transfer status %i, %s %i, tot %i\n", st, (wr ? "put" : "got"), got, tot);
            fprintf(stderr, "Did you forget to enable 'blast' mode on the target?\n");
			goto bail;
		}
		tot += got;
/*		printf("%4d\n", tot); */
	}

    if ( clock_gettime( CLOCK_MONOTONIC, &now ) ) {
		fprintf(stderr, "Unable to read clock/time: %s\n", strerror( errno ) );
		goto bail;
	}

    diff = (double)then.tv_sec + ((double)then.tv_nsec)*1.0E-9;
    diff = (double)now.tv_sec + ((double)now.tv_nsec)*1.0E-9 - diff;

	printf("Successfully transferred (%sing) %i bytes in %6.3f s (%6.3f MB/s)\n", (wr ? "writ" : "read"), tot, diff, ((double)tot)/diff/1.0E6);

	rv = 0;

bail:
	if ( cfg ) {
		libusb_free_config_descriptor( cfg );
	}
	if ( devh ) {
		if ( intf >= 0 ) {
			libusb_release_interface( devh, intf );
		}
		libusb_close( devh );
	}
	if ( ctx ) {
		libusb_exit( ctx );
	}
	return rv;
}

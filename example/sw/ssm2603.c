#include <stdio.h>
#include <getopt.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <inttypes.h>
#include <time.h>
#include <stdlib.h>
#include <math.h>

#include <linux/i2c-dev.h>
#include <linux/i2c.h>

#include <sys/ioctl.h>

static int
rr(int fd, int a, int r)
{
struct i2c_msg             msgs[2];
struct i2c_rdwr_ioctl_data iob;
uint8_t                    b0[1];
uint8_t                    b1[2];

	iob.msgs  = msgs;
	iob.nmsgs = sizeof(msgs)/sizeof(msgs[0]);

	msgs[0].addr  = a;
    msgs[0].flags = 0;
    msgs[0].len   = sizeof(b0);
    msgs[0].buf   = b0;

	msgs[1].addr  = a;
    msgs[1].flags = I2C_M_RD;
    msgs[1].len   = sizeof(b1);
    msgs[1].buf   = b1;

	b0[0] = (r<<1);
    memset( b1, 0xff, sizeof(b1) );

	if ( ioctl(fd, I2C_RDWR, &iob) < 0 ) {
		fprintf(stderr, "regRead: ioctl(I2C_RDWR) failed: %s\n", strerror(errno));
		return -1;
	}

	return (b1[1]<<8) | b1[0];
}

static int
wr(int fd, int a, int r, int v)
{
struct i2c_msg             msgs[1];
struct i2c_rdwr_ioctl_data iob;
uint8_t                    b0[2];

	iob.msgs  = msgs;
	iob.nmsgs = sizeof(msgs)/sizeof(msgs[0]);

	msgs[0].addr  = a;
	msgs[0].flags = 0;
	msgs[0].len   = sizeof(b0);
	msgs[0].buf   = b0;

	b0[0] = (r<<1) | ((v >> 8) & 1);
	b0[1] = v & 0xff;

	if ( ioctl(fd, I2C_RDWR, &iob) < 0 ) {
		fprintf(stderr, "regWrite: ioctl(I2C_RDWR) failed: %s\n", strerror(errno));
		return -1;
	}
	return 0;
}

static void usage(const char *nm)
{
	printf("usage: %s [-hDRMS] [-a <i2c_addr>] [-d <i2c-chardev>] {<reg>[=<val>] }\n", nm);
	printf("   -h        : this message\n");
	printf("   -D        : dump SSM2603 register contents\n");
	printf("   -R        : reset SM2603\n");
	printf("   -a <a>    : I2C address (default: 0x1a)\n");
	printf("   -d <d>    : I2C driver char device\n");
	printf("   <r>[=<v>] : read or write (with value <v>) register <r>\n");
	printf("               multiple <r>[=<v>] commands may be listed\n");
	printf("   -M        : initialize for master mode (16bit, 48kHz,\n");
	printf("               12.288MHz ref, I2S format).\n");
}

struct rv {
	int         r;
	int         v;
	signed long t;
};

#define Cmid (10.1E-6*1.2) /* Zybo + 20% */

#define TACT ((long)round(Cmid * 25000/3.5))

static struct rv cfgMst[] = {
	{ r : 0x6, v : 0x052, t:        0 }, /* power essential parts            */
	{ r : 0x0, v : 0x01f, t:        0 }, /* unmute + vol left                */
	{ r : 0x1, v : 0x01f, t:        0 }, /* unmute + vol left                */
	{ r : 0x2, v : 0x17f, t:        0 }, /* DAC vol (7f max in 1db steps)    */
	{ r : 0x5, v : 0x000, t:        0 }, /* disable DAC mute                 */
	{ r : 0x4, v : 0x012, t:        0 }, /* enable DAC to mixer              */
    { r : 0x8, v : 0x000, t:        0 }, /* 48kHz (12.288MHz ref)            */
    { r : 0x7, v : 0x042, t:        0 }, /* MASTER MODE, 16-bit samples      */
    { r : 0x9, v : 0x001, t:    -TACT }, /* activate                         */
    { r : 0x6, v : 0x042, t:        0 }, /* power-on OUT                     */
};

static void u_sleep(unsigned long us)
{
struct timespec zzz;

	if ( 0 == us ) {
		return;
	}
	zzz.tv_sec  = us/1000000;
	zzz.tv_nsec = (us - (1000000*zzz.tv_sec))*1000;
	while ( nanosleep( &zzz, &zzz ) ) {
		if ( EINTR != errno ) {
			fprintf(stderr, "Fatal error: nanosleep failed: %s\n", strerror(errno));
			abort();
		}
	}
}

static int rst(int fd, int a)
{
int              st = wr(fd, a, 0x0f, 0);
	if ( st < 0 ) {
		fprintf(stderr, "RESET failed\n");
		return st;
	}
	u_sleep( 100000 );
	return 0;
}

int
main(int argc, char **argv)
{
const char *fnam = "/dev/i2c-0";
int         i2ca = 0x1a;
int         fd   = -1;
int         rv   = 1;
int         r, v, i;
int         opt;
int        *i_p;
int         dump  = 0;
int         doRst = 0;
struct rv  *cfg   = 0;
int         cfgl  = 0;

	while ( (opt = getopt(argc, argv, "d:a:DhMR")) >= 0 ) {
		i_p = 0;
		switch ( opt ) {
			case 'd': fnam  = optarg;      break;
            case 'a': i_p   = &i2ca;       break;
            case 'D': dump  =  1;          break;
            case 'R': doRst =  1;          break;
			case 'M': cfg   =  cfgMst; cfgl = sizeof(cfgMst)/sizeof(cfgMst[0]); break;
            case 'h': usage( argv[0] );    return 0;
		}
		if ( i_p && 1 != sscanf( optarg, "%i", &i2ca ) ) {
			fprintf(stderr, "Unable to parse argument to option '-%c'\n", opt);
			goto bail;
		}
	}

	if ( (fd = open( fnam, O_RDWR )) < 0 ) {
		fprintf(stderr, "Unable to open %s: %s\n", fnam, strerror(errno));
		goto bail;
	}

	if ( (cfg || doRst) && rst( fd, i2ca ) ) {
		goto bail;
	}

	if ( cfg ) {
		for ( i = 0; i < cfgl; i++ ) {
			if ( cfg[i].t < 0 ) {
				u_sleep( -cfg[i].t );
			}
			if ( wr( fd, i2ca, cfg[i].r, cfg[i].v ) ) {
				fprintf(stderr, "Error writing register %d; aborting config\n", i);
				goto bail;
			}
			if ( cfg[i].t > 0 ) {
				u_sleep(  cfg[i].t );
			}
		}
	}
	
    for ( i = optind; i < argc; i++ ) {
		switch ( sscanf( argv[i], "%i=%i", &r, &v ) ) {
			case 1:
				v = rr( fd, i2ca, r );
				if ( v >= 0 ) {
					printf("R[%2i]: 0x%03x\n", r, v);
				}
				break;
			case 2:
				wr(fd, i2ca, r, v);
				break;
			default:
				fprintf(stderr, "invalid command: '%s'\n", argv[i]);
				break;
		}
	}

	if ( dump ) {
		for ( i = 0; i <= 18; i++ ) {
			if ( i >= 10 && i <= 14 )
				continue;
			if ( (v = rr(fd, i2ca, i)) < 0 ) {
				goto bail;
			}
			printf("R[%2i]: 0x%03x\n", i, v);
		}
	}

	rv = 0;

bail:
	if ( fd >= 0 ) {
		close( fd );
	}
	return rv;
}

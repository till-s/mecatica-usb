/*
 * Copyright Till Straumann, 2024. Licensed under the EUPL-1.2 or later.
 * You may obtain a copy of the license at
 *   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
 * This notice must not be removed.
 */

/*
 * Test the USB CDCAcm Example design's ACM interrupt endpoint.
 * Use the TIOCMIWAIT ioctl to wait for a change of one of the
 * modem lines (CDC, RI, CTS, DSR) which can be asserted in the
 * FPGA code (ACM function).
 */

#include <stdio.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <getopt.h>
#include <string.h>

static
void usage(const char *nm)
{
	printf("usage: %s [-d tty_device] [-n num_irqs]\n", nm);
	printf("    -n    : number of interrupts to process (< 0 => indefinite)\n");
	printf("            default: 0 (just print current status of lines)\n");
}

int
main(int argc, char **argv)
{
int                rv = 1;
int                opt;
const char        *dev = "/dev/ttyACM0";
int                fd  = -1;
int                mdm;
int                i;
int                n = 0;
int               *i_p;

	while ( (opt = getopt( argc, argv, "d:hn:" ) ) > 0 ) {
		i_p = 0;
		switch ( opt ) {
			case 'd' : dev = optarg;      break;
			case 'n' : i_p = &n;          break;

			default:
			case 'h' : usage( argv[0] );  return 0;
		}
		if ( i_p && 1 != sscanf( optarg, "%i", i_p ) ) {
			fprintf( stderr, "Error: Unable to scan argument of option -%c\n", opt );
			return 1;
		}
	}

	if ( (fd = open( dev, O_RDWR )) < 0 ) {
		perror("error opening tty");
		goto bail;
	}

	i = 0;
	while ( 1 ) {

		if ( ioctl( fd, TIOCMGET, &mdm ) ) {
			perror("ioctl(TIOCMGET) failed\n");
			goto bail;
		}

		printf("Modem bits:");
		if( ( mdm & TIOCM_LE  ) ) printf( " DSR" );
		if( ( mdm & TIOCM_DTR ) ) printf( " DTR" );
		if( ( mdm & TIOCM_RTS ) ) printf( " RTS" );
		if( ( mdm & TIOCM_ST  ) ) printf( " STX" );
		if( ( mdm & TIOCM_SR  ) ) printf( " SRX" );
		if( ( mdm & TIOCM_CTS ) ) printf( " CTS" );
		if( ( mdm & TIOCM_CD  ) ) printf( " DCD" );
		if( ( mdm & TIOCM_RNG ) ) printf( " RNG" );
		if( ( mdm & TIOCM_DSR ) ) printf( " DSR" );
		printf("\n");

		if ( i == n )
			break;

		mdm = TIOCM_RNG | TIOCM_CD | TIOCM_CTS | TIOCM_DSR;

		printf( "Waiting for modem interrupt\n");
		if ( ioctl( fd, TIOCMIWAIT, mdm ) ) {
			perror("ioctl(TIOCMIWAIT) failed\n");
			goto bail;
		}

		if ( n >= 0 ) {
			i++;
		}
	}

	rv = 0;
bail:
	if ( fd >= 0 ) {
		close( fd );
	}
	return rv;
}

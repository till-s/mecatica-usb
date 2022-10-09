GHDL=ghdl

VIVADO=/opt/ghdl/v1.0.0-gcc/vivado-2018.03/

SRCS+= UlpiIO.vhd UlpiPkg.vhd UlpiIOTb.vhd

PROG=upliiotb

all: $(PROG)

%.o: %.vhd
	$(GHDL) -a $(addprefix -P,$(VIVADO)) $<

$(PROG): $(SRCS:%.vhd=%.o)
	$(GHDL) -e $(addprefix -P,$(VIVADO)) $@

UlpiIOTb.o: UlpiIO.o UlpiPkg.o
UlpiIO.o: UlpiPkg.o

clean:
	$(RM) $(SRCS:%.vhd=%.o) work-*.cf ulpiiotb e~*.o $(PROG) dump.ghw

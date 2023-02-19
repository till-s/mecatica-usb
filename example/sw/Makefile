-include config-local.mk

ifeq ($(KERNELDIR),)
KERNELDIR := /lib/modules/$(shell uname -r)/build/
endif

XA:=arm
CROSS:=$(addsuffix -linux-,$(XA))

all: blktst zynq-demo modules


blktst: blktst.c
	$(CC) -O2 -Wall -o $@ $< -lusb-1.0

zynq-demo: zynq-demo.c
	$(CROSS)$(CC) -O2 -Wall -o $@ $<

mod-objs := drv_fifo_eth.o
# Kernel Module:
obj-m := drv_fifo_eth.o

modules:
	make -C $(KERNELDIR) $(addprefix CROSS_COMPILE=,$(CROSS)) $(addprefix ARCH=,$(XA)) M=$(PWD) modules

modclean:
	make -C $(KERNELDIR) $(addprefix CROSS_COMPILE=,$(CROSS)) $(addprefix ARCH=,$(XA)) M=$(PWD) clean

clean: modclean
	$(RM) *.o *~ core .depend .*.cmd *.ko *.mod.c .tmp_versions blktst modules.order Module.symvers zynq-demo

.PHONY: clean modclean all modules

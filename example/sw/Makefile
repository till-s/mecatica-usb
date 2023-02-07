-include config-local.mk

ifeq ($(KERNELDIR),)
KERNELDIR := /lib/modules/$(shell uname -r)/build/
endif

XA:=arm
CROSS:=$(addsuffix -linux-,$(XA))


blktst: blktst.c
	$(CROSS)$(CC) -O2 -Wall -o $@ $< -lusb-1.0

mod-objs := drv_fifo_eth.o
# Kernel Module:
obj-m := drv_fifo_eth.o

modules:
	make -C $(KERNELDIR) $(addprefix CROSS_COMPILE=,$(CROSS)) $(addprefix ARCH=,$(XA)) M=$(PWD) modules

clean:
	$(RM) *.o *~ core .depend .*.cmd *.ko *.mod.c .tmp_versions blktst modules.order Module.symvers

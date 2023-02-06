-include config-local.mk

blktst: blktst.c
	$(CC) -O2 -Wall -o $@ $< -lusb-1.0

mod-objs := drv_fifo_eth.o
# Kernel Module:
obj-m := drv_fifo_eth.o

ifndef KERNELDIR
KERNELDIR := /lib/modules/$(shell uname -r)/build/
endif

ARCH:=arm
CROSS:=$(addsuffix -linux-,$(ARCH))

modules:
	make -C $(KERNELDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS) M=$(PWD) modules

clean:
	$(RM) *.o *~ core .depend .*.cmd *.ko *.mod.c .tmp_versions blktst modules.order Module.symvers

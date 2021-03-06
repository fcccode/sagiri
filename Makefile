OBJS = kobj/main.o kobj/entry.o kobj/stdio.o kobj/console.o kobj/uart.o kobj/mm.o kobj/string.o kobj/debug.o kobj/acpi.o kobj/lapic.o kobj/seg.o kobj/vectors.o kobj/trap.o kobj/trapasm.o kobj/ioapic.o kobj/cpu.o kobj/malloc.o kobj/vm.o kobj/spinlock.o kobj/proc.o kobj/kthread.o kobj/switch.o kobj/schedule.o kobj/syscall.o kobj/sysenter.o kobj/ide.o kobj/fs.o
UPROGRAMS = uobj/hello.exe uobj/echo.exe uobj/init.exe uobj/sh.exe uobj/cat.exe uobj/ls.exe uobj/mkdir.exe uobj/rmdir.exe uobj/rm.exe uobj/forktest.exe
QEMU = qemu-system-x86_64
CFLAGS = -fno-pic -static -fno-builtin -fno-strict-aliasing -Wall -MD -ggdb -fno-omit-frame-pointer -ffreestanding -fno-common -nostdlib -gdwarf-2 -m64 -DX64 -mcmodel=large -mtls-direct-seg-refs -mno-red-zone -fno-stack-protector
LDFLAGS = -m elf_x86_64 -nodefaultlibs
all: kernel.img fs.img
kernel.img: out/bootblock out/enable out/kernel.elf
	dd if=/dev/zero of=kernel.img count=10000 2> /dev/null
	dd if=out/bootblock of=kernel.img conv=notrunc 2> /dev/null
	dd if=out/enable of=kernel.img seek=1 conv=notrunc 2> /dev/null
	dd if=out/kernel.elf of=kernel.img seek=2 conv=notrunc 2> /dev/null
kobj/%.o: kernel/*/%.c
	@mkdir -p kobj
	gcc $(CFLAGS) -Ikernel/ -c -o $@ $<
kobj/%.o: kernel/*/%.S
	@mkdir -p kobj
	gcc $(CFLAGS) -Ikernel/ -c -o $@ $<
uobj/%.o: user/%.c
	@mkdir -p uobj
	gcc $(CFLAGS) -Iuser/ -c -o $@ $<
uobj/%.o: user/%.S
	@mkdir -p uobj
	gcc $(CFLAGS) -Iuser/ -c -o $@ $<
uobj/%.exe: uobj/%.o uobj/lib.o uobj/libasm.o
	@mkdir -p uobj
	ld $(LDFLAGS) -T user/user.ld -o $@ $< uobj/lib.o uobj/libasm.o
	objdump -S $@ > $@.asm
	objdump -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $@.sym
out/bootblock: boot/bootasm.S boot/bootmain.c
	@mkdir -p out
	gcc -fno-builtin -fno-pic -m32 -nostdinc -O -o out/bootmain.o -c boot/bootmain.c
	gcc -fno-builtin -fno-pic -m32 -nostdinc -o out/bootasm.o -c boot/bootasm.S
	ld -m elf_i386 -nodefaultlibs -N -e start -Ttext 0x7C00 -o out/bootblock.o out/bootasm.o out/bootmain.o
	objdump -S out/bootblock.o > out/bootblock.asm
	objcopy -S -O binary -j .text out/bootblock.o out/bootblock
	gcc tools/sign.c -o out/sign
	out/sign
out/enable: boot/enable64.S
	@mkdir -p out
	gcc -fno-builtin -fno-pic -m64 -nostdinc -o out/enable64.o -c boot/enable64.S
	ld -m elf_x86_64 -nodefaultlibs -N -e start -Ttext 0x7E00 -o out/enable.o out/enable64.o
	objdump -S out/enable.o > out/enable.asm
	objcopy -S -O binary -j .text out/enable.o out/enable
out/entrymp: kernel/init/entrymp.S
	@mkdir -p out
	gcc -fno-builtin -fno-pic -m32 -nostdinc -O -o out/entrymp.o -c kernel/init/entrymp.S
	ld -m elf_i386 -nodefaultlibs -N -e start -Ttext 0x7000 -o out/entrympblock.o out/entrymp.o
	objdump -S out/entrympblock.o > out/entrympblock.asm
	objcopy -S -O binary -j .text out/entrympblock.o out/entrymp
out/entrymp64: kernel/init/entrymp64.S
	@mkdir -p out
	gcc -fno-builtin -fno-pic -m64 -nostdinc -O -o out/entrymp64.o -c kernel/init/entrymp64.S
	ld -m elf_x86_64 -nodefaultlibs -N -e start -Ttext 0x7200 -o out/entrymp64block.o out/entrymp64.o
	objdump -S out/entrymp64block.o > out/entrymp64block.asm
	objcopy -S -O binary -j .text out/entrymp64block.o out/entrymp64
out/kernel.elf: $(OBJS) kernel/kernel.ld out/entrymp out/entrymp64
	ld $(LDFLAGS) -T kernel/kernel.ld -o out/kernel.elf $(OBJS) -b binary out/entrymp out/entrymp64
	objdump -S out/kernel.elf > out/kernel.asm
	objdump -t out/kernel.elf | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > out/kernel.sym
fs.img: tools/makefs.c $(UPROGRAMS) LICENSE.txt
	gcc tools/makefs.c -o out/makefs
	out/makefs
clean: 
	rm -rf out kobj uobj kernel.img fs.img
ifndef CPUS
CPUS := 4
endif
QEMUOPTS = -net none -drive file=kernel.img,index=0,media=disk,format=raw -drive file=fs.img,index=1,media=disk,format=raw -smp $(CPUS) -m 1024
qemu: kernel.img fs.img
	$(QEMU) -serial mon:stdio -nographic $(QEMUOPTS)
debug: kernel.img fs.img
	$(QEMU) -serial mon:stdio -s -S -nographic $(QEMUOPTS)
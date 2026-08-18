C_SOURCES = $(wildcard kernel/*.c drivers/*.c)
HEADERS = $(wildcard kernel/*.h drivers/*.h)
OBJ = ${C_SOURCES:.c=.o}

all: os-image

os-image: boot/boot.bin kernel.bin
	cat $^ > os.img

kernel.bin: kernel/kernel_entry.o ${OBJ}
	ld -m elf_i386 -o $@ -Ttext 0x1000 $^ --oformat binary

%.o: %.c ${HEADERS}
	gcc -m32 -ffreestanding -fno-pie -fno-pic -fno-stack-protector -c $< -o $@

%.o: %.asm
	nasm $< -f elf32 -o $@

%.bin: %.asm
	nasm $< -f bin -o $@
	
run:
	qemu-system-i386 -drive file=os.img,format=raw,if=floppy -d int,cpu_reset -no-reboot -no-shutdown

clean:
	rm -rf *.bin *.o os.img
	rm -rf kernel/*.o boot/*.bin drivers/*.o
build: boot.asm
	nasm boot.asm -f bin -o boot.bin

run: boot.bin
	cat boot.bin dist/kernel.bin > os.img && \
	qemu-system-i386 -drive file=os.img,format=raw,if=floppy -d int,cpu_reset -D qemu.log -no-reboot -no-shutdown

build: boot.asm
	nasm boot.asm -f bin -o boot.bin

run: boot.bin
	qemu-system-i386 -drive file=boot.bin,format=raw,if=floppy -d int,cpu_reset -D qemu.log -no-reboot -no-shutdown

[org 0x7c00]
  KERNEL_OFFSET equ 0x1000
  mov [BOOT_DRIVE] , dl

  mov bp, 0x9000
  mov sp, bp

  call load_kernel
  call switch_to_pm

  jmp $

%include "boot/gdt.asm"
%include "boot/print.asm"
%include "boot/print_pm.asm"
%include "boot/switch_to_pm.asm"
%include "boot/disk_load.asm"

[bits 16]
load_kernel :
  mov bx, KERNEL_OFFSET
  mov dh, 15
  mov dl, [BOOT_DRIVE]

  call disk_load
  ret

[bits 32]
BEGIN_PM:
  call KERNEL_OFFSET

  jmp $

BOOT_DRIVE db 0

times 510-($-$$) db 0
dw 0xaa55
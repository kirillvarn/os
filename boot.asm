[org 0x7c00]
  mov bp, 0x9000 ; Set the stack.
  mov sp, bp

  mov bx, MSG_REAL_MODE
  call print

  call switch_to_pm ; Note that we never return from here.

  jmp $

%include "gdt.asm"
%include "print.asm"
%include "print_pm.asm"
%include "switch_to_pm.asm"

[bits 32]
BEGIN_PM:
  mov ebx, MSG_PROT_MODE
  call clear_screen

  call print_string_pm ; Use our 32 - bit print routine.
  jmp $

[bits 32]
clear_screen:
    mov edi, 0xb8000
    mov ecx, 80 * 25
    mov ax, 0x0f20       ; 0x20 = space, 0x0f = white on black

    rep stosw
    ret

MSG_REAL_MODE db "Started in 16 - bit Real Mode", 0
MSG_PROT_MODE db "Successfully landed in 32 - bit Protected Mode",0

times 510-($-$$) db 0
dw 0xaa55
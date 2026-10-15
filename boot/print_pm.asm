[bits 32]
VIDEO_MEMORY equ 0xb8000
WHITE_ON_BLACK equ 0x0f

; in: ESI = string, EDI = screen address, AH = colour; clobbers: AL, ESI, EDI.
print_string_pm:
  lodsb

  mov ah, WHITE_ON_BLACK
  cmp al, 0
  je print_string_pm_done

  stosw

  jmp print_string_pm

print_string_pm_done:
  ret
print:
  pusha
  mov ah, 0x0e
  call print_string
  popa
  ret

print_string:
  mov al, [bx]

  cmp al, 0
  je return

  int 0x10
  inc bx

  jmp print_string


; dx contains printable value
print_hex:
  pusha

  mov bx, 5

print_hex_loop:
  mov cx, dx
  and cx, 0xF

  mov di, cx
  mov al, [HEX_LOOKUP + di]
  mov byte [HEX_OUT + bx], al

  dec bx

  cmp bx, 1
  je print_hex_loop_end

  shr dx, 4

  jmp print_hex_loop

print_hex_loop_end:
  mov bx, HEX_OUT
  call print

  popa
  ret

return:
  ret

HEX_OUT: db '0x0000',13,10,0
HEX_LOOKUP: db '0123456789ABCDEF'

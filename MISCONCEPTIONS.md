# Misconceptions this project teaches

This kernel follows the classic "write an OS from scratch" tutorial path. It works, but many of its
choices are shortcuts that real operating systems do not take. Each entry below says what this
project does, what a real OS does instead, and why the difference matters.

Legend: **Here** = this project, **Real** = Linux / Windows / BSD and serious hobby kernels.

---

## 1. Booting and loading

### 1.1 The bootloader guesses the kernel size
- **Here:** `boot/boot.asm:17` loads a hardcoded number of sectors (`mov dh, 32`). When the kernel
  grew past 15 sectors, the end of it (including its strings) was never loaded, and the screen
  showed numbers without their text.
- **Real:** The kernel is an ELF (or PE) file. The bootloader (GRUB, Limine, systemd-boot, UEFI)
  reads its headers and loads exactly the parts listed there.
- **Why it matters:** Nothing ever checks the kernel's size here. When the kernel outgrows the
  hardcoded number, it breaks quietly, with no error message.

### 1.2 Floppy, CHS addressing and BIOS calls
- **Here:** `boot/disk_load.asm:6-8` reads with BIOS `int 0x13` in CHS mode: fixed cylinder 0,
  head 0, starting at sector 2. Reading more than 17 sectors runs past the end of a floppy
  track, and some BIOSes refuse that.
- **Real:** UEFI firmware reads files from a FAT partition. Older BIOS loaders use LBA
  (extended `int 0x13`, `ah=0x42`). After boot, the kernel has its own disk drivers
  (AHCI, NVMe) and never calls the BIOS again.
- **Why it matters:** CHS geometry and floppies are obsolete, and UEFI machines have no BIOS
  `int 0x13` at all.

### 1.3 No A20 gate, no memory map
- **Here:** The boot code never enables the A20 line and never asks the firmware which RAM is
  usable. It works only because everything sits below 1 MB and QEMU enables A20 already.
- **Real:** The loader gets a memory map (BIOS `E820` or UEFI `GetMemoryMap`) and hands it to the
  kernel. The kernel's memory manager starts from that map.
- **Why it matters:** Without a memory map, a kernel can't know where RAM is. That's the base of
  everything in section 3.

### 1.4 Flat binary, link order as the entry point, `.bss` never zeroed
- **Here:** `Makefile:11` links with `--oformat binary`. The entry point works only because
  `kernel_entry.o` happens to be listed first. `.bss` (`idt`, `interrupt_handlers`,
  `key_buffer`) is never zeroed. The code assumes it is all zero, which holds only because QEMU's
  RAM and the extra sectors read past the end of the image happen to be zeros.
- **Real:** A linker script places sections and names the entry symbol. The entry code (or the
  loader) zeroes `.bss` before any C code runs.
- **Why it matters:** `irq_handler` trusts that empty slots in `interrupt_handlers` are `0`. On
  real hardware a leftover non-zero value becomes a jump to a random address.

### 1.5 Host GCC instead of a cross-compiler
- **Here:** `Makefile:14` uses the system `gcc -m32` with a few `-fno-*` flags.
- **Real:** Hobby kernels use a cross-compiler (`i686-elf-gcc`) plus `-nostdlib -fno-builtin`.
  Linux carefully controls every code-generation flag.
- **Why it matters:** The host compiler assumes a Linux user-space target. That's why `strlen`
  produced a "use `<string.h>`" hint: GCC treats `strlen` as a known libc function unless told
  otherwise.

---

## 2. Interrupts

### 2.1 Manual `cli` / `sti` in every stub
- **Here:** Every stub starts with `cli`, and both common stubs run `sti` before `iret`
  (`cpu/interrupt.asm:28`, `:48`).
- **Real:** The IDT entries are *interrupt gates* (`flags = 0x8E`, `cpu/idt.c:11`), so the CPU
  already clears IF on entry. `iret` restores the saved EFLAGS, IF included. Both instructions do
  nothing useful.
- **Why it matters:** It teaches that the handler must turn interrupts on and off by hand. In
  reality, the gate type and EFLAGS decide this.

### 2.2 The register snapshot is passed by value
- **Here:** `isr_handler(registers_t r)` and `irq_handler(registers_t r)` receive a *copy* of the
  saved registers, built on the stack by the assembly stub.
- **Real:** Handlers receive a **pointer** to the saved frame (`struct pt_regs *` in Linux).
- **Why it matters:**
  - Changes to `r` are lost, so this design can never do system calls (return a value in `eax`) or
    switch tasks (swap `esp` / `eip`).
  - In the cdecl calling convention, a called function may reuse its argument slots as scratch
    space. The stub later does `pop ebx` from that same area to restore `ds`, so a compiler
    optimization could quietly corrupt the segment registers.

### 2.3 Wrong error-code assumptions in exception stubs
- **Here:** `isr17` (Alignment Check), `isr21` (Control Protection) and `isr30` (Security) push a
  fake error code of `0`, but the CPU already pushes a real one for these. The stack layout
  ends up off by 4 bytes, and `iret` returns to a garbage address.
- **Real:** The stubs follow the Intel SDM table of which vectors push an error code.
- **Why it matters:** The tutorial's rule "8 and 10-14 have error codes" is from the 1990s and
  incomplete.

### 2.4 Exceptions print a message and then return
- **Here:** `isr_handler` (`cpu/isr.c:128`) prints the exception name and returns.
- **Real:** A fault in user code kills the process (or sends it a signal). A fault in kernel code
  is a panic (Linux "oops"). A page fault in a real OS usually means "load this page", after
  which the instruction is retried on purpose.
- **Why it matters:** For faults like #GP or #PF, returning re-runs the same bad instruction. That
  gives an endless stream of the same message.
- **Also:** some names in `exception_messages[]` (`cpu/isr.c:90`) are wrong or outdated:
  - 15 is reserved, not "Unknown Interrupt".
  - 19 is the SIMD floating-point exception.
  - 20 is the virtualization exception.
  - 21 is Control Protection.

### 2.5 Interrupts enabled before handlers exist, and every IRQ unmasked
- **Here:**
  - `cpu/isr.c:65` unmasks *all 16* PIC lines.
  - `irq_install` (`cpu/isr.c:11-18`) runs `sti` *before* the timer and keyboard handlers are
    registered.
- **Real:** All lines start masked. A driver registers its handler, and only then unmasks its own
  line.
- **Why it matters:** Any device can fire before anyone is listening. Here it works only because
  unregistered interrupts are silently dropped, which also hides real problems (for example
  spurious IRQ 7 and IRQ 15).

---

## 3. What's missing that defines an OS

### 3.1 No memory management
- **Here:** Everything sits at fixed physical addresses: kernel at `0x1000`, stack at `0x90000`,
  screen at `0xb8000`. Paging is never turned on.
- **Real:** Paging (virtual memory) is the core of the OS. Every process has its own address
  space, and the kernel usually lives in the "higher half". A physical page allocator hands out
  RAM from the memory map (see 1.3).
- **Why it matters:** Without paging there is no isolation, no protection and no processes.

### 3.2 Everything runs in ring 0, and the GDT is only a formality
- **Here:** `boot/gdt.asm` has just a kernel code and a kernel data segment. There's no user mode
  and no TSS.
- **Real:** The GDT is set up mainly to define user segments (ring 3) and a TSS, so the CPU knows
  which kernel stack to use when user code is interrupted. Segmentation itself is unused (flat).
- **Why it matters:** The prompt says "Type something, it will go through the kernel", but
  there's no "outside the kernel". The shell, the keyboard driver and the kernel are one program
  with full hardware access.

### 3.3 The whole shell runs inside the keyboard interrupt
- **Here:** `keyboard_callback` prints, edits the buffer and calls `user_input()`
  (`drivers/keyboard.c:38`). All of this happens inside the IRQ 1 handler, with interrupts off.
- **Real:** An interrupt handler does the minimum: read the scancode, put it in a queue, wake a
  task. The rest runs later in normal context (Linux "top half / bottom half", Windows DPCs).
- **Why it matters:** While a long command runs, the timer and every other device are blocked.
  Even `END` only halts because of this flaw (see 3.4).

### 3.4 `hlt` is not "stop the computer"
- **Here:** `user_input` runs `hlt` on `END` (`kernel/kernel.c:19`) and prints "Stopping the
  CPU".
- **Real:** `hlt` means "sleep until the next interrupt". It halts permanently here only because
  the code runs inside an interrupt handler, where interrupts are already off. Real kernels use
  `cli; hlt` in a loop to stop for good, ACPI to power off, and `hlt` (in a loop) as the idle
  loop.
- **Why it matters:** Move this code out of the interrupt (as in 3.3) and `END` stops working:
  the next timer tick wakes the CPU again. Also, `jmp $` in `kernel/kernel_entry.asm:7` and
  `boot/boot.asm:27` keeps the CPU busy at 100% instead of idling with `hlt`.

### 3.5 "libc" inside the kernel
- **Here:** The `libc/` folder holds `strlen`, `strcmp` and memory helpers.
- **Real:** A kernel never links the C library. It has its own small helper library (Linux
  `lib/`). "libc" is the user-space library that sits *on top of* the kernel's system calls.
- **Why it matters:** The folder name mixes up the two sides of the system-call boundary that
  section 3.2 never builds.

---

## 4. Hardware the way it was in 1990

### 4.1 8259 PIC and 8253/8254 PIT
- **Here:** The interrupt controller is the 8259 PIC pair, and the timer is the PIT (`cpu/timer.c`).
- **Real:**
  - Interrupts go through the Local APIC + I/O APIC, or MSI/MSI-X messages straight from PCIe
    devices.
  - Time comes from the LAPIC timer, TSC-deadline or HPET.
  - The PIC is turned off at boot, and the PIT is used at most to calibrate other timers.
- **Why it matters:** The PIC can't route interrupts to more than one CPU core.

### 4.2 VGA text mode, with the cursor register as the source of truth
- **Here:** Text is written to `0xb8000`. `print_char` reads the cursor position *back from the
  VGA chip* (`get_cursor`, 4 port operations) for every single character.
- **Real:**
  - UEFI machines often have no text mode. The kernel draws characters into a pixel framebuffer
    (GOP) with its own font.
  - The terminal's state (cursor, colours, scrollback) lives in kernel memory, and the hardware
    is only the output.
- **Why it matters:** Port I/O is slow, and hardware is not a variable. Reading state back from
  devices is something real drivers avoid.

### 4.3 PS/2 keyboard, scancode set 1, key presses only
- **Here:** One lookup table for scancodes `0-57` (`drivers/keyboard.c`).
  - Key releases and `0xE0` extended keys are dropped (`scancode > SC_MAX`).
  - Shift and Caps Lock are not handled, so every letter is uppercase.
  - The PS/2 controller is never initialized.
- **Real:** Keyboards are USB HID devices behind an xHCI controller. PS/2 is legacy emulation.
  Drivers track press/release state and build characters from a keymap.

### 4.4 Port I/O helpers without `volatile`
- **Here:** `kernel/low_level.c:3,13` use plain `__asm__` for `in`. Because the asm has an output
  and isn't `volatile`, GCC may remove it if the result looks unused, or merge two identical
  reads into one.
- **Real:** `static inline` helpers with `asm volatile` (Linux `inb` / `outb`), often with a
  `"memory"` clobber.
- **Why it matters:** Reading a device port twice can give two different answers (the keyboard
  data port does). The compiler must not "optimize" device reads.

---

## 5. Build bugs (not concepts, but they cause confusing errors)

- `Makefile:2`: `cpu/*.j` should be `cpu/*.h`. Editing a `cpu/` header doesn't trigger a rebuild,
  so old `.o` files stay in use.
- `Makefile:3`: `${C_SOURCES:.c=.o cpu/interrupt.o}` adds `cpu/interrupt.o` once per C file
  instead of once.
- `make clean` doesn't delete `cpu/*.o` or `libc/*.o`.
- `libc/string.c`: `int_to_ascii(INT_MIN)` overflows, since `-n` doesn't fit in an `int`.

---

## Where to learn the real way

- OSDev Wiki, "Bare Bones" and "Meaty Skeleton": cross-compiler, Multiboot/GRUB, linker script,
  `.bss` setup.
- Intel SDM Vol. 3, chapter 6 (interrupts and exceptions, including the error-code table).
- *Operating Systems: Three Easy Pieces* (free online): paging, processes, scheduling.
- xv6 (MIT): a small but *real* Unix kernel with paging, user mode, system calls and a scheduler.

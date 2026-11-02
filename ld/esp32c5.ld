/* Bare-metal layout for the ESP32-C5.
 *
 * The ROM bootloader reads this image from flash offset 0x2000, copies every
 * segment into HP SRAM and jumps to _start. There is no second-stage
 * bootloader and no flash mapping, so code, data and stack all live in SRAM.
 *
 * ESP-IDF's own map ends the app region at 0x4084E5A0, where its second-stage
 * bootloader starts; stay a little below that. */

INCLUDE esp32c5.rom.ld        /* ets_printf, ets_delay_us, memset, ...        */
INCLUDE esp32c5.rom.libc.ld   /* memcpy, memcmp, strlen, ...                  */
INCLUDE esp32c5.rom.api.ld    /* esp_rom_* aliases                            */

ENTRY(_start)

MEMORY
{
  ram (rwx) : ORIGIN = 0x40800000, LENGTH = 0x4B000
}

SECTIONS
{
  .text : ALIGN(4)
  {
    KEEP(*(.text.init))       /* _start must sit at the image entry */
    *(.text .text.*)
  } > ram

  .rodata : ALIGN(4)
  {
    *(.rodata .rodata.* .srodata .srodata.*)
  } > ram

  .data : ALIGN(4)
  {
    _data_start = .;
    *(.data .data.* .sdata .sdata.*)
    _data_end = .;
  } > ram
  __global_pointer$ = _data_start + 0x800;

  /* Thread-local storage. crt0 copies .tdata and zeroes .tbss into a block
   * (.tls) and points tp at it; every `tlocal` access is tp + a link-time
   * constant, which is what freertos-riscv32's local-exec model emits. */
  .tdata : ALIGN(16)
  {
    __tdata_start = .;
    *(.tdata .tdata.*)
    __tdata_end = .;
  } > ram
  .tbss : ALIGN(16)
  {
    __tbss_start = .;
    *(.tbss .tbss.* .tcommon)
    __tbss_end = .;
  } > ram

  .bss (NOLOAD) : ALIGN(4)
  {
    _bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > ram

  .tls (NOLOAD) : ALIGN(16)
  {
    __tls_start = .;
    . += __tbss_end - __tdata_start;
    . = ALIGN(16);
    __tls_end = .;
  } > ram

  _heap_start = .;
  _stack_top = ORIGIN(ram) + LENGTH(ram);

  /DISCARD/ : { *(.eh_frame*) *(.comment) }
}

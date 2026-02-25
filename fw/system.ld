MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    RAM (rwx) : ORIGIN = 0x10008000, LENGTH = 4K /* After 32KB framebuffer */
}

SECTIONS {
  __stacktop = ORIGIN(RAM) + LENGTH(RAM);

  . = ORIGIN(ROM);
  .text :
  {
    start*(.text)
    *(.text)
    *(.text.*)
    *(.rodata)
    *(.rodata.*)
  } > ROM

  . = ORIGIN(RAM);
  .data :
  {
    . = ALIGN(4);
    _data_start = .;
    *(.sdata)
    *(.sdata.*)
    *(.data)
    *(.data.*)
    _data_end = .;
  } > RAM AT> ROM
  .bss :
  {
    . = ALIGN(4);
    _bss_start = .;
    *(.sbss)
    *(.sbss.*)
    *(.bss)
    *(.bss.*)
    _bss_end = .;
  } > RAM
  _idata_start = LOADADDR(.data);
}

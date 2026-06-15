ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x10000000, LENGTH = 2048K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 256K
}

SECTIONS
{
    /* Second stage bootloader */
    .boot2 :
    {
        __boot2_start__ = .;
        KEEP(*(.boot2))
        __boot2_end__ = .;
    } > FLASH

    /* Vector table */
    .vectors :
    {
        . = ALIGN(256);
        KEEP(*(.vectors))
    } > FLASH

    /* Program code and read-only data */
    .text :
    {
        *(.text*)
        *(.rodata*)
    } > FLASH

    /* Load address of .data section */
    _sidata = LOADADDR(.data);

    /* Initialized data section in RAM */
    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT> FLASH

    /* Uninitialized data section in RAM */
    .bss :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /* Stack top is at the end of RAM */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}

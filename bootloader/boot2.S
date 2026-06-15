// ----------------------------------------------------------------------------
// Second stage boot code (derived from generic_03h.S)
// Copyright (c) 2019-2021 Raspberry Pi (Trading) Ltd.
// SPDX-License-Identifier: BSD-3-Clause
// ----------------------------------------------------------------------------

.syntax unified
.cpu cortex-m0plus
.thumb

.section .boot2, "ax"
.global _stage2_boot
.type _stage2_boot, %function
_stage2_boot:
    push {lr}

    // Base address of XIP_SSI_BASE (0x18000000)
    ldr r3, =0x18000000

    // Disable SSI
    movs r1, #0
    str r1, [r3, #0x08] // SSI_SSIENR_OFFSET

    // Set baud rate (SPI_CLKDIV = 4)
    movs r1, #4
    str r1, [r3, #0x14] // SSI_BAUDR_OFFSET

    // Set CTRLR0_XIP = 0x001f0300
    ldr r1, =0x001f0300
    str r1, [r3, #0x00] // SSI_CTRLR0_OFFSET

    // Set SPI_CTRLR0_XIP = 0x03000218
    ldr r1, =0x03000218
    ldr r0, =0x180000f4 // XIP_SSI_BASE + SSI_SPI_CTRLR0_OFFSET
    str r1, [r0]

    // NDF = 0
    movs r1, #0
    str r1, [r3, #0x04] // SSI_CTRLR1_OFFSET

    // Re-enable SSI
    movs r1, #1
    str r1, [r3, #0x08] // SSI_SSIENR_OFFSET

    // Exit sequence
    pop {r0}
    cmp r0, #0
    beq vector_into_flash
    bx r0

vector_into_flash:
    ldr r0, =0x10000100                 // Address of main vector table
    ldr r1, =0xe000ed08                 // VTOR address (PPB_BASE + M0PLUS_VTOR_OFFSET)
    str r0, [r1]                        // Point VTOR to the vector table
    ldmia r0, {r0, r1}                  // Load stack pointer (r0) and reset handler (r1)
    msr msp, r0                         // Set main stack pointer
    bx r1                               // Jump to reset handler

.align 4
.ltorg

// Pad out to exactly 252 bytes so that the checksum can be placed at the end of 256 bytes
.space 252 - (. - _stage2_boot)
.word 0 // Checksum placeholder

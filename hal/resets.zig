// Copyright (c) Zig Embedded Group contributors
//
// This software is provided 'as-is', without any express or implied
// warranty. In no event will the authors be held liable for any damages
// arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it
// freely, subject to the following restrictions:
//
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgment in the product documentation would be
//    appreciated but is not required.
// 2. Altered source versions must be plainly marked as such, and must not be
//    misrepresented as being the original software.
// 3. This notice may not be removed or altered from any source distribution.

// Some of the code of this file is taken from
// microzig/port/raspberrypi/rp2xxx/src/hal/resets.zig
// Only the rp2350 parts of the code have been taken out from the copied code
const std = @import("std");

/// Bitmask representation of the RP2040 reset registers.
/// The bit fields correspond to the peripherals mapped in the RESET register.
/// Reference: RP2040 Datasheet, Section 2.14.3 (Register Map for RESETS).
pub const Mask = packed struct(u32) {
    adc: bool = true,
    busctrl: bool = true,
    dma: bool = true,
    i2c0: bool = true,
    i2c1: bool = true,
    io_bank0: bool = true,
    io_qspi: bool = true,
    jtag: bool = true,
    pads_bank0: bool = true,
    pads_qspi: bool = true,
    pio0: bool = true,
    pio1: bool = true,
    pll_sys: bool = true,
    pll_usb: bool = true,
    pwm: bool = true,
    rtc: bool = true,
    spi0: bool = true,
    spi1: bool = true,
    syscfg: bool = true,
    sysinfo: bool = true,
    tbman: bool = true,
    timer: bool = true,
    uart0: bool = true,
    uart1: bool = true,
    usbctrl: bool = true,
    padding: u7 = 0,

    /// Helper to generate a mask with only one peripheral bit enabled.
    pub inline fn only(tag: std.meta.FieldEnum(Mask)) Mask {
        var empty = std.mem.zeroes(Mask);
        @field(empty, @tagName(tag)) = true;
        return empty;
    }
};
/// Mask of all peripherals.
/// Defaults to all true due to the default initializers on the Mask struct fields.
pub const all: Mask = .{};

/// Mask of peripherals that should be reset at initialization.
/// We do NOT reset critical system blocks (like QSPI flash lines, system clocks PLL, and syscfg)
/// to avoid CPU / memory execution crashes.
pub const init: Mask = val: {
    var tmp: Mask = .{};
    tmp.io_qspi = false;
    tmp.pads_qspi = false;
    tmp.pll_usb = false;
    tmp.usbctrl = false;
    tmp.syscfg = false;
    tmp.pll_sys = false;
    break :val tmp;
};

/// Mask of peripherals that depend only on clk_sys and clk_ref clocks,
/// meaning they do not require extra clock tree configuration to be operated.
pub const depend_on_sys_ref: Mask = val: {
    var tmp: Mask = .{};
    tmp.adc = false;
    tmp.spi0 = false;
    tmp.spi1 = false;
    tmp.uart0 = false;
    tmp.uart1 = false;
    tmp.usbctrl = false;
    tmp.rtc = false;
    break :val tmp;
};

// Everything beyond this point is my handwritten code

/// Base address of the Subsystem Resets controller.
/// According to RP2040 Datasheet, Section 2.14.3 (Register Map), the Resets block starts here.
pub const Resets_base: usize = 0x4000c000;
pub const ResetRegister = enum(u8) {
    reset = 0x00,
    wdsel = 0x04,
    done = 0x08,
};

// Atomic register access offsets.
// According to RP2040 Datasheet, Section 2.1.2 (Atomic Register Access), these write-modifiers
// allow bitwise set, clear, and toggle operations without read-modify-write races.
pub const Alias = enum(u16) {
    rw = 0x0000,
    xor = 0x1000,
    set = 0x2000,
    clr = 0x3000,
};

pub inline fn get_reset_register(register: ResetRegister, alias: Alias) *volatile u32 {
    return @ptrFromInt(Resets_base | @intFromEnum(register) | @intFromEnum(alias));
}

/// Put the peripherals specified in the mask into reset state.
/// Writing 1 to a bit in the RESET register forces that peripheral into reset.
pub inline fn reset_block(mask: Mask) void {
    get_reset_register(.reset, .set).* = @bitCast(mask);
}

/// Release the peripherals specified in the mask from reset state.
/// Writing 1 to a bit in the CLR alias of the RESET register clears that bit to 0, releasing the reset hold.
pub inline fn unreset_block(mask: Mask) void {
    get_reset_register(.reset, .clr).* = @bitCast(mask);
}

/// Wait until the peripherals specified in the mask have finished resetting and are active.
/// According to RP2040 Datasheet Section 2.14.3, bits in RESET_DONE are set to 1 when reset is completed.
pub fn wait_for_reset_done(mask: Mask) void {
    const raw_mask = @as(u32, @bitCast(mask));
    while (get_reset_register(.done, .rw).* & raw_mask != raw_mask) {
        asm volatile ("" ::: .{ .memory = true });
    }
}

/// Release the block from reset and wait until it is ready for use.
pub fn unreset_block_wait(mask: Mask) void {
    unreset_block(mask);
    wait_for_reset_done(mask);
}

/// Resets the specified peripherals by setting their reset bits to 1,
/// clearing them to 0, and then waiting for the reset to complete.
pub fn reset(mask: Mask) void {
    const raw_mask = @as(u32, @bitCast(mask));
    get_reset_register(.reset, .rw).* = raw_mask;
    get_reset_register(.reset, .rw).* = 0;
    wait_for_reset_done(mask);
}

const Register = @import("register.zig").Register;
const Pll = @import("pll.zig").Pll;

pub const Clocks_base: u32 = 0x4000_8000;

pub const Generator = enum(usize) {
    gpout0 = 0,
    gpout1 = 1,
    gpout2 = 2,
    gpout3 = 3,
    ref = 4,
    sys = 5,
    peri = 6,
    usb = 7,
    adc = 8,
    rtc = 9,

    pub inline fn ctrl(self: Generator) Register(u32) {
        return .{ .address = Clocks_base + @intFromEnum(self) * 12 + 0 };
    }

    pub inline fn div(self: Generator) Register(u32) {
        return .{ .address = Clocks_base + @intFromEnum(self) * 12 + 4 };
    }

    pub inline fn selected(self: Generator) Register(u32) {
        return .{ .address = Clocks_base + @intFromEnum(self) * 12 + 8 };
    }
};

const CTRL_ENABLE_MASK: u32 = 1 << 11;
const CTRL_SRC_MASK: u32 = 0x3;
const CTRL_AUX_SRC_MASK: u32 = 0x1e0; // Bits 8:5

/// Source definitions for clocks, mapping to the AUXSRC and SRC register bit values.
pub const Source = enum {
    rosc,
    xosc,
    pll_sys,
    pll_usb,
    clk_sys,
    clk_ref,
};

/// Get the value to write to the CTRL.SRC field (only for ref and sys).
fn src_value(generator: Generator, source: Source) u2 {
    return switch (generator) {
        .sys => switch (source) {
            .clk_ref => 0,
            else => 1, // Any aux source requires SRC = 1
        },
        .ref => switch (source) {
            .rosc => 0,
            .xosc => 2,
            else => 1, // Any aux source requires SRC = 1
        },
        else => unreachable,
    };
}

/// Get the value to write to the CTRL.AUXSRC field (bits 8:5).
fn auxsrc_value(generator: Generator, source: Source) u4 {
    return switch (generator) {
        .sys => switch (source) {
            .pll_sys => 0,
            .pll_usb => 1,
            .rosc => 2,
            .xosc => 3,
            else => unreachable,
        },
        .ref => switch (source) {
            .pll_usb => 0,
            else => unreachable,
        },
        .peri => switch (source) {
            .clk_sys => 0,
            .pll_sys => 1,
            .pll_usb => 2,
            .rosc => 3,
            .xosc => 4,
            else => unreachable,
        },
        .usb, .adc, .rtc => switch (source) {
            .pll_usb => 0,
            .pll_sys => 1,
            .rosc => 2,
            .xosc => 3,
            else => unreachable,
        },
        else => unreachable,
    };
}

/// Busy-wait for at least the specified number of system clock cycles.
/// On Cortex-M0+, each loop iteration of subs + bne takes 3 cycles.
fn delay_cycles(cycles: u32) void {
    if (cycles == 0) return;
    // Divide cycles by 3 because each loop iteration takes ~3 cycles
    var count = cycles / 3 + 1;
    asm volatile (
        \\1:
        \\  subs %[count], #1
        \\  bne 1b
        : [count] "+r" (count),
        :
        : .{ .cpsr = true, .memory = true }
    );
}

fn configure_generator(generator: Generator, source: Source, divisor: u32, sys_freq: u32) void {
    // 1. If it's a glitchless clock (ref or sys)
    if (generator == .ref or generator == .sys) {
        // If we want to switch to an AUX source, we must first switch SRC away from AUX (to rosc or clk_ref)
        // to prevent glitching the clock line during AUXSRC modification.
        const is_aux = switch (generator) {
            .sys => source != .clk_ref,
            .ref => source != .rosc and source != .xosc,
            else => unreachable,
        };

        if (is_aux) {
            // Clear SRC to switch away from AUX
            const val = generator.ctrl().read();
            generator.ctrl().write(val & ~CTRL_SRC_MASK);
            // Wait for selection to reflect
            const bit: u32 = 0; // bit 0 (rosc for ref, clk_ref for sys)
            while ((generator.selected().read() & (@as(u32, 1) << @intCast(bit))) == 0) {
                asm volatile ("" ::: .{ .memory = true });
            }

            // Now configure the new auxiliary source safely
            const aux_val = auxsrc_value(generator, source);
            const ctrl_val = generator.ctrl().read();
            generator.ctrl().write((ctrl_val & ~CTRL_AUX_SRC_MASK) | (@as(u32, aux_val) << 5));

            // Set divisor before enabling the new clock path
            generator.div().write(divisor << 8);

            // Switch glitchless mux to AUX
            const new_ctrl = generator.ctrl().read();
            generator.ctrl().write((new_ctrl & ~CTRL_SRC_MASK) | src_value(generator, source));
            while ((generator.selected().read() & (@as(u32, 1) << @intCast(src_value(generator, source)))) == 0) {
                asm volatile ("" ::: .{ .memory = true });
            }
        } else {
            // Switching to a non-aux glitchless source is simple:
            const new_ctrl = generator.ctrl().read();
            generator.ctrl().write((new_ctrl & ~CTRL_SRC_MASK) | src_value(generator, source));
            while ((generator.selected().read() & (@as(u32, 1) << @intCast(src_value(generator, source)))) == 0) {
                asm volatile ("" ::: .{ .memory = true });
            }
            generator.div().write(divisor << 8);
        }
    } else {
        // 2. For auxiliary-only clocks (peri, usb, adc, rtc), we must disable first to prevent glitches
        const ctrl_val = generator.ctrl().read();
        generator.ctrl().write(ctrl_val & ~CTRL_ENABLE_MASK);

        // Wait for the clock to stop cleanly based on the frequency ratio
        const freq = 48_000_000 / divisor; // approx frequency for delay calculation
        const delay = sys_freq / freq + 1;
        delay_cycles(delay);

        // Write the divisor
        if (generator != .peri) {
            generator.div().write(divisor << 8);
        }

        // Set the new aux source
        const aux_val = auxsrc_value(generator, source);
        const new_ctrl = (generator.ctrl().read() & ~CTRL_AUX_SRC_MASK) | (@as(u32, aux_val) << 5);
        generator.ctrl().write(new_ctrl);

        // Re-enable
        generator.ctrl().write(new_ctrl | CTRL_ENABLE_MASK);
    }
}

pub fn init() void {
    // Disable resus (resuscitation feature) during clock initialization
    // SYS_RESUS_CTRL is at offset 0x78
    const sys_resus_ctrl = Register(u32){ .address = Clocks_base | 0x78 };
    sys_resus_ctrl.write(0);

    // 1. Ensure clk_sys is running from clk_ref (glitchless transition)
    // and wait for selection to complete.
    configure_generator(.sys, .clk_ref, 1, 6_500_000);

    // 2. Switch clk_ref to xosc (12 MHz)
    configure_generator(.ref, .xosc, 1, 6_500_000);

    // 3. Now that clk_ref and clk_sys are safely on the 12 MHz XOSC,
    // configure and lock pll_sys to 125 MHz and pll_usb to 48 MHz.
    Pll.sys.configure(.{
        .fb_div = 125,
        .ref_div = 1,
        .post_div1 = 6,
        .post_div2 = 2,
    });
    Pll.usb.configure(.{
        .fb_div = 100,
        .ref_div = 1,
        .post_div1 = 5,
        .post_div2 = 5,
    });

    // 4. Switch clk_sys to pll_sys (125 MHz)
    configure_generator(.sys, .pll_sys, 1, 12_000_000);

    // 5. Configure clk_peri to run from clk_sys at 125 MHz
    configure_generator(.peri, .clk_sys, 1, 125_000_000);

    // 6. Configure clk_usb to run from pll_usb at 48 MHz
    configure_generator(.usb, .pll_usb, 1, 125_000_000);

    // 7. Configure clk_adc to run from pll_usb at 48 MHz
    configure_generator(.adc, .pll_usb, 1, 125_000_000);

    // 8. Configure clk_rtc to run from xosc divided down to 46.875 kHz
    // Divisor is 12 MHz / 46.875 kHz = 256.
    configure_generator(.rtc, .xosc, 256, 125_000_000);
}

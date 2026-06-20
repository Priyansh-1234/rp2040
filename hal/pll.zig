const assert = @import("std").debug.assert;
const Register = @import("register.zig").Register;
const Xosc = @import("xosc.zig");
const Resets = @import("resets.zig");

pub const PLL_sys_base: u32 = 0x4002_8000;
pub const PLL_usb_base: u32 = 0x4002_c000;

pub const Configuration = struct {
    fb_div: u12,
    ref_div: u6,
    post_div1: u3,
    post_div2: u3,

    pub fn frequency(config: Configuration) u32 {
        return (@as(u32, Xosc.xosc_frequency) / config.ref_div) * config.fb_div / (config.post_div1 * config.post_div2);
    }
};

pub const Pll = enum(usize) {
    sys = PLL_sys_base,
    usb = PLL_usb_base,

    pub inline fn cs(pll: Pll) Register(CS) {
        return .{ .address = @intFromEnum(pll) | cs_offset };
    }

    pub inline fn pwr(pll: Pll) Register(Pwr) {
        return .{ .address = @intFromEnum(pll) | pwr_offset };
    }

    pub inline fn fbdiv_int(pll: Pll) Register(FbdivInt) {
        return .{ .address = @intFromEnum(pll) | fbdiv_int_offset };
    }

    pub inline fn prim(pll: Pll) Register(Prim) {
        return .{ .address = @intFromEnum(pll) | prim_offset };
    }

    pub fn reset(pll: Pll) void {
        const mask: Resets.Mask = switch (pll) {
            .sys => .{ .pll_sys = true },
            .usb => .{ .pll_usb = true },
        };
        Resets.reset_block(mask);
        Resets.unreset_block_wait(mask);
    }

    pub fn is_locked(pll: Pll) bool {
        return pll.cs().read().lock == 1;
    }

    pub fn configure(pll: Pll, comptime config: Configuration) void {
        // See section 2.18.2 Calculating Pll Parameters
        // These Limits are taken from there
        comptime {
            assert(config.fb_div >= 16 and config.fb_div <= 320);
            assert(config.post_div1 >= 1 and config.post_div2 >= 1);
            assert(config.post_div1 >= config.post_div2);

            const reference_frequency = @as(u32, Xosc.xosc_frequency) / config.ref_div;
            assert(reference_frequency > 5_000_000);
            const vco_frequency = reference_frequency * config.fb_div;
            assert(reference_frequency <= vco_frequency / 16);
        }

        // If the pll was previously already setup with the same config, don't touch
        // anything
        // Idea taken from microzig
        // microzig/ports/raspberrypi/rp2xxx/src/hal/pll.zig
        if (pll.is_locked() and
            config.fb_div == pll.fbdiv_int().read().fb_div and
            config.ref_div == pll.cs().read().ref_div and
            config.post_div1 == pll.prim().read().post_div1 and
            config.post_div2 == pll.prim().read().post_div2)
        {
            return;
        }

        pll.reset();

        // See section 2.18.3 Configuration
        // The programming sequence for the PLL is as follows:
        // • Program the reference clock divider (is a divide by 1 in the RP2040 case)
        // • Program the feedback divider
        // • Turn on the main power and VCO
        // • Wait for the VCO to lock (i.e. keep its output frequency stable)
        // • Set up post dividers and turn them on

        pll.cs().modify(.{ .ref_div = config.ref_div, .bypass = 0 });
        pll.fbdiv_int().modify(.{ .fb_div = config.fb_div });

        pll.pwr().modify(.{
            .pll_pd = 0,
            .vco_pd = 0,
            .post_div_pd = 1,
            .dsm_pd = 1,
        });

        while (!pll.is_locked()) {
            asm volatile ("" ::: .{ .memory = true });
        }

        pll.prim().modify(.{
            .post_div1 = config.post_div1,
            .post_div2 = config.post_div2,
        });

        pll.pwr().modify(.{ .post_div_pd = 0 });
    }
};

// See 2.18.4 List of Registers
const cs_offset = 0x0;
const pwr_offset = 0x4;
const fbdiv_int_offset = 0x8;
const prim_offset = 0xc;

const CS = packed struct(u32) {
    ref_div: u6,
    reserved_1: u2,
    bypass: u1,
    reserved_2: u22,
    lock: u1,
};

const Pwr = packed struct(u32) {
    pll_pd: u1,
    reserved_1: u1,
    dsm_pd: u1,
    post_div_pd: u1,
    reserved_2: u1,
    vco_pd: u1,
    reserved_3: u26,
};

// NOTE: this PLL does not support fractional division
const FbdivInt = packed struct(u32) {
    fb_div: u12,
    reserved: u20,
};

const Prim = packed struct(u32) {
    reserved_1: u12,
    post_div2: u3,
    reserved_2: u1,
    post_div1: u3,
    reserved_3: u13,
};

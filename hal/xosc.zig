const Register = @import("register.zig").Register;

pub const XOSC_base: u32 = 0x4002_4000;
pub const xosc_frequency = 12_000_000;
pub const startup_delay_ms = 1;
pub const startup_delay_value = (xosc_frequency * startup_delay_ms) / (256 * 1000);

inline fn ctrl() Register(Ctrl) {
    return .{ .address = XOSC_base | ctrl_offset };
}

inline fn status() Register(Status) {
    return .{ .address = XOSC_base | status_offset };
}

inline fn dormant() Register(Dormant) {
    return .{ .address = XOSC_base | dormant_offset };
}

inline fn startup() Register(Startup) {
    return .{ .address = XOSC_base | startup_offset };
}

inline fn count() Register(Count) {
    return .{ .address = XOSC_base | count_offset };
}

pub fn init() void {
    ctrl().modify(.{ .frequency_range = .@"1_15MHZ" });
    startup().modify(.{ .delay = @as(u14, @intCast(startup_delay_value)) });
    ctrl().modify(.{ .enable = .enable });

    while (status().read().stable == 0) {
        asm volatile ("" ::: .{ .memory = true });
    }
}

// See section 2.16.7 List of Registers

const ctrl_offset = 0x00;
const status_offset = 0x04;
const dormant_offset = 0x08;
const startup_offset = 0x0c;
const count_offset = 0x1c;

const Ctrl = packed struct(u32) {
    pub const enable_enum = enum(u12) {
        disable = 0xd1e,
        enable = 0xfab,
    };
    pub const frequency_enum = enum(u12) {
        @"1_15MHZ" = 0xaa0,
        reserved_1 = 0xaa1,
        reserved_2 = 0xaa2,
        reserved_3 = 0xaa3,
    };

    frequency_range: frequency_enum,
    enable: enable_enum,
    reserved: u8,
};

const Status = packed struct(u32) {
    pub const frequency_enum = enum(u2) {
        @"1_15MHZ" = 0x0,
        reserved_1 = 0x1,
        reserved_2 = 0x2,
        reserved_3 = 0x3,
    };

    frequency_range: frequency_enum,
    reserved_1: u10,
    enabled: u1,
    reserved_2: u11,
    bad_write: u1,
    reserved_3: u6,
    stable: u1,
};

// WARNING: stop the PLLs before selecting dormant mode
// WARNING: setup the irq before selecting dormant mode
const Dormant = packed struct(u32) {
    pub const dormant_enum = enum(u32) {
        dormant = 0x636f_6d61,
        wake = 0x7761_6b65,
    };

    value: dormant_enum,
};

const Startup = packed struct(u32) {
    delay: u14,
    reserved_1: u6,
    x4: u1,
    reserved_2: u11,
};

const Count = packed struct(u32) {
    down_counter: u8,
    reserved: u24,
};

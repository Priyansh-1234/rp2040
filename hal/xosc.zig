pub const XOSC_base = 0x4002_4000;
pub const xosc_frequency = 12_000_000;
pub const startup_delay_ms = 1;
pub const startup_delay_value = (xosc_frequency * startup_delay_ms) / (256 * 1000);

pub const Xosc = extern struct {
    ctrl: Ctrl,
    status: Status,
    dormant: Dormant,
    startup: Startup,
    padding: [3]u32,
    count: Count,
};

pub inline fn get_xosc_registers() *volatile Xosc {
    return @ptrFromInt(XOSC_base);
}

pub fn init() void {
    const xosc = get_xosc_registers();

    var ctrl = xosc.ctrl;
    ctrl.frequency_range = .@"1_15MHZ";
    xosc.ctrl = ctrl;

    var startup = xosc.startup;
    startup.delay = @truncate(startup_delay_value);
    xosc.startup = startup;

    while (xosc.status.stable == 0) {
        asm volatile ("" ::: .{ .memory = true });
    }
}

pub const Ctrl = packed struct(u32) {
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

pub const Status = packed struct(u32) {
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
pub const Dormant = packed struct(u32) {
    pub const dormant_enum = enum(u32) {
        dormant = 0x636f6d61,
        wake = 0x77616b65,
    };
    value: dormant_enum,
};

pub const Startup = packed struct(u32) {
    delay: u14,
    reserved_1: u6,
    x4: u1,
    reserved_2: u11,
};

pub const Count = packed struct(u32) {
    down_counter: u8,
    reserved: u24,
};

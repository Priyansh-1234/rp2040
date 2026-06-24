const Register = @import("register.zig").Register;

pub var sys_tick_count: u32 = 0;
pub const PPB_base: u32 = 0xe000_0000;

pub const Systick = struct {
    pub inline fn ctrl_status() Register(ControlAndStatus) {
        return .{ .address = PPB_base | 0xe010 };
    }
    pub inline fn reload() Register(u32) {
        return .{ .address = PPB_base | 0xe014 };
    }
    pub inline fn current() Register(u32) {
        return .{ .address = PPB_base | 0xe018 };
    }

    pub fn init(ticks: u24) void {
        ctrl_status().modify(.{
            .enable = .disable,
            .tick_int = .dont_assert,
            .clock_source = .processor,
        });

        reload().write(ticks - 1);
        current().write(0);

        ctrl_status().modify(.{
            .enable = .enable,
            .tick_int = .assert,
            .clock_source = .processor,
        });
    }
};

const enable_enum = enum(u1) {
    disable = 0,
    enable = 1,
};
const assert_enum = enum(u1) {
    dont_assert = 0,
    assert = 1,
};
const clock_enum = enum(u1) {
    external = 0,
    processor = 1,
};

const ControlAndStatus = packed struct(u32) {
    enable: enable_enum,
    tick_int: assert_enum,
    clock_source: clock_enum,
    reserved_1: u13,
    count_flag: u1,
    reserved_2: u15,
};

pub fn get_systick_count() u32 {
    const ptr: *volatile const u32 = &sys_tick_count;
    return ptr.*;
}

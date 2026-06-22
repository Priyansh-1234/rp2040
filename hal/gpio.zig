const Register = @import("register.zig").Register;

pub const Io_bank0_base: u32 = 0x4001_4000;
pub const Pad_bank0_base: u32 = 0x4001_c000;
pub const Sio_base: u32 = 0xd000_0000;

pub const Sio = struct {
    pub inline fn gpio_in() Register(u32) {
        return .{ .address = Sio_base | 0x004 };
    }

    pub inline fn gpio_out() Register(u32) {
        return .{ .address = Sio_base | 0x010 };
    }
    pub inline fn gpio_out_set() Register(u32) {
        return .{ .address = Sio_base | 0x014 };
    }
    pub inline fn gpio_out_clr() Register(u32) {
        return .{ .address = Sio_base | 0x018 };
    }
    pub inline fn gpio_out_xor() Register(u32) {
        return .{ .address = Sio_base | 0x01c };
    }

    pub inline fn gpio_oe() Register(u32) {
        return .{ .address = Sio_base | 0x020 };
    }
    pub inline fn gpio_oe_set() Register(u32) {
        return .{ .address = Sio_base | 0x024 };
    }
    pub inline fn gpio_oe_clr() Register(u32) {
        return .{ .address = Sio_base | 0x028 };
    }
    pub inline fn gpio_oe_xor() Register(u32) {
        return .{ .address = Sio_base | 0x02c };
    }
};

pub const GetPinError = error{
    PinNotFound,
};

pub inline fn getPin(pin: u5) GetPinError!Pin {
    if (pin >= 30) {
        return error.PinNotFound;
    }
    return @enumFromInt(pin);
}

pub const Pin = enum(u5) {
    _,

    pub inline fn status_reg(self: Pin) Register(GpioStatus) {
        return .{ .address = Io_bank0_base | 0x8 * @as(u32, @intCast(@intFromEnum(self))) };
    }

    pub inline fn ctrl_reg(self: Pin) Register(GpioCtrl) {
        return .{ .address = Io_bank0_base | 0x8 * @as(u32, @intCast(@intFromEnum(self))) | 0x4 };
    }

    pub inline fn pad_reg(self: Pin) Register(PadCtrl) {
        return .{ .address = Pad_bank0_base + 0x4 + 0x4 * @as(u32, @intCast(@intFromEnum(self))) };
    }

    pub inline fn mask(self: Pin) u32 {
        return @as(u32, 1) << @intCast(@intFromEnum(self));
    }

    pub inline fn set_pull(pin: Pin, pull: Pull) void {
        switch (pull) {
            .none => pin.pad_reg().modify(.{ .pull_up_enable = 0, .pull_down_enable = 0 }),
            .down => pin.pad_reg().modify(.{ .pull_up_enable = 0, .pull_down_enable = 1 }),
            .up => pin.pad_reg().modify(.{ .pull_up_enable = 1, .pull_down_enable = 0 }),
        }
    }

    pub inline fn set_direction(pin: Pin, direction: Direction) void {
        switch (direction) {
            .in => Sio.gpio_oe_clr().write(pin.mask()),
            .out => Sio.gpio_oe_set().write(pin.mask()),
        }
    }

    pub inline fn set_value(pin: Pin, value: u1) void {
        switch (value) {
            0 => Sio.gpio_out_clr().write(pin.mask()),
            1 => Sio.gpio_out_set().write(pin.mask()),
        }
    }

    pub inline fn toggle_value(pin: Pin) void {
        Sio.gpio_out_xor().write(pin.mask());
    }

    pub inline fn read(pin: Pin) u1 {
        return if (Sio.gpio_in().read() & pin.mask() != 0)
            1
        else
            0;
    }

    pub inline fn set_input_enabled(pin: Pin, enable: bool) void {
        pin.pad_reg().modify(.{ .input_enabled = @intFromBool(enable) });
    }

    pub inline fn set_output_disabled(pin: Pin, disable: bool) void {
        pin.pad_reg().modify(.{ .output_disabled = @intFromBool(disable) });
    }

    pub inline fn set_function(pin: Pin, function: Function) void {
        pin.pad_reg().modify(.{
            .input_enabled = 1,
            .output_disabled = 0,
        });

        pin.ctrl_reg().modify(.{
            .func_sel = function,
            .out_over = .normal,
            .oe_over = .normal,
            .in_over = .normal,
            .irq_over = .normal,
        });
    }

    pub inline fn set_slew(pin: Pin, slew: Slew) void {
        pin.pad_reg().modify(.{ .slew = slew });
    }

    pub inline fn set_schmitt_trigger_enable(pin: Pin, enable: bool) void {
        pin.pad_reg().modify(.{ .schmitt = @intFromBool(enable) });
    }

    pub inline fn set_drive_strength(pin: Pin, drive: Drive) void {
        pin.pad_reg().modify(.{ .drive = drive });
    }
};

pub const Overdrive = enum(u2) {
    normal = 0x0,
    invert = 0x1,
    low = 0x2,
    high = 0x3,
};

pub const Slew = enum(u1) {
    slow = 0,
    fast = 1,
};

pub const Drive = enum(u2) {
    @"2MA" = 0x0,
    @"4MA" = 0x1,
    @"8MA" = 0x2,
    @"12MA" = 0x3,
};

pub const Function = enum(u5) {
    xip = 0,
    spi = 1,
    uart = 2,
    i2c = 3,
    pwm = 4,
    sio = 5,
    pio0 = 6,
    pio1 = 7,
    gpck = 8,
    usb = 9,
    disabled = 0x1f,
};

pub const Direction = enum(u1) {
    in = 0,
    out = 1,
};

pub const Pull = enum(u2) {
    none = 0,
    down = 1,
    up = 2,
};

const GpioStatus = packed struct(u32) {
    reserved_1: u8,
    out_from_peri: u1,
    out_to_pad: u1,
    reserved_2: u2,
    oe_from_peri: u1,
    oe_to_pad: u1,
    reserved_3: u3,
    in_from_pad: u1,
    reserved_4: u1,
    in_to_peri: u1,
    reserved_5: u4,
    irq_from_pad: u1,
    reserved_6: u1,
    irq_to_proc: u1,
    reserved_7: u5,
};

const GpioCtrl = packed struct(u32) {
    func_sel: Function,
    reserved_1: u3,
    out_over: Overdrive,
    reserved_2: u2,
    oe_over: Overdrive,
    reserved_3: u2,
    in_over: Overdrive,
    reserved_4: u10,
    irq_over: Overdrive,
    reserved_5: u2,
};

const PadCtrl = packed struct(u32) {
    slew: Slew,
    schmitt: u1,
    pull_down_enable: u1,
    pull_up_enable: u1,
    drive: Drive,
    input_enabled: u1,
    output_disabled: u1,
    reserved: u24,
};

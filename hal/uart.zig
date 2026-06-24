const Register = @import("register.zig").Register;
const Resets = @import("resets.zig");

pub const UART0_base: u32 = 0x4003_4000;
pub const UART1_base: u32 = 0x4003_8000;

pub const Uart = enum(u32) {
    Uart0 = UART0_base,
    Uart1 = UART1_base,

    pub inline fn data(uart: Uart) Register(u32) {
        return .{ .address = @intFromEnum(uart) | 0x000 };
    }
    pub inline fn flags(uart: Uart) Register(Flags) {
        return .{ .address = @intFromEnum(uart) | 0x018 };
    }
    pub inline fn integral_baud_rate(uart: Uart) Register(u32) {
        return .{ .address = @intFromEnum(uart) | 0x024 };
    }
    pub inline fn fractional_baud_rate(uart: Uart) Register(u32) {
        return .{ .address = @intFromEnum(uart) | 0x028 };
    }
    pub inline fn line_control(uart: Uart) Register(LineControl) {
        return .{ .address = @intFromEnum(uart) | 0x02c };
    }

    pub inline fn control(uart: Uart) Register(Control) {
        return .{ .address = @intFromEnum(uart) | 0x030 };
    }

    // initializes the uart according to the datasheet steps
    // Section 4.2.7 Programmer's Model
    // The datasheet lists the following steps to initialize the uart
    // To initialise the UART, the uart_init function takes the following steps:
    // • Deassert the reset
    // • Enable clk_peri
    // • Set enable bits in the control register
    // • Enable the FIFOs
    // • Set the baud rate divisors
    // • Set the format
    pub fn init(uart: Uart, baud_rate: u32, clk_peri: u32) void {
        switch (uart) {
            .Uart0 => {
                Resets.reset_block(.only(.uart0));
                Resets.unreset_block_wait(.only(.uart0));
            },
            .Uart1 => {
                Resets.reset_block(.only(.uart1));
                Resets.unreset_block_wait(.only(.uart1));
            },
        }

        uart.control().modify(.{
            .uart_enable = .enable,
            .transmit_enable = .enable,
            .receive_enable = .enable,
        });

        // Section 4.2.7.1 Baud Rate Calculation
        // UART runs from the clk_peri
        // Baud Rate Divisor = f_(clk_peri) / (16 * baud_rate)
        const baud_rate_divisor: f32 = @as(f32, @floatFromInt(clk_peri)) / (16.0 * @as(f32, @floatFromInt(baud_rate)));
        const integral_rate = @as(u16, @intFromFloat(baud_rate_divisor));
        const fractional_rate: u6 = @intFromFloat((baud_rate_divisor - @as(f32, @floatFromInt(integral_rate))) * 64.0 + 0.5);

        uart.integral_baud_rate().write(integral_rate);
        uart.fractional_baud_rate().write(fractional_rate);

        uart.line_control().modify(.{ .word_length = .@"8", .fifo_enable = .enable });
    }

    // Writes a byte into the data register of the uart
    // if the transmit fifo is full this function will block
    pub inline fn write_byte(uart: Uart, byte: u8) void {
        while (uart.flags().read().transmit_fifo_full) {
            asm volatile ("" ::: .{ .memory = true });
        }
        uart.data().write(byte);
    }

    // Writes a byte into the data register of the uart
    // returns whether the write would block
    pub inline fn write_byte_block(uart: Uart, byte: u8) bool {
        if (uart.flags().read().transmit_fifo_full) {
            return true;
        }
        uart.data().write(byte);
        return false;
    }

    // Writes a byte slice to the uart.
    // This write can block.
    // This function also adds a carriage return '\r' after a line feed '\n'
    pub inline fn write_slice_cr(uart: Uart, slice: []const u8) void {
        for (slice[0..]) |char| {
            if (char == '\n') {
                uart.write_byte('\r');
            }
            uart.write_byte(char);
        }
    }

    // Writes a byte slice to the uart.
    // This write can block.
    pub inline fn write_slice(uart: Uart, slice: []const u8) void {
        for (slice[0..]) |char| {
            uart.write_byte(char);
        }
    }

    // Writes a byte slice to the uart.
    // We try to write till the uart trasmit is full, and then
    // return the amount of bytes written.
    // Adds a carriage return '\r' after a line feed '\n'
    pub inline fn write_slice_block_cr(uart: Uart, slice: []const u8) usize {
        for (slice[0..], 0..) |char, index| {
            if (char == '\n') {
                if (uart.write_byte_block('\r')) {
                    return index;
                }
            }
            if (uart.write_byte_block(char)) {
                return index;
            }
        }
        return slice.len;
    }

    // Writes a byte slice to the uart.
    // We try to write till the uart trasmit is full, and then
    // return the amount of bytes written.
    pub inline fn write_slice_block(uart: Uart, slice: []const u8) usize {
        for (slice[0..], 0..) |char, index| {
            if (uart.write_byte_block(char)) {
                return index;
            }
        }
        return slice.len;
    }

    pub fn read_byte(uart: Uart) u8 {
        while (uart.flags().read().receive_fifo_empty) {
            asm volatile ("" ::: .{ .memory = true });
        }
        return @truncate(uart.data().read());
    }
};

// See Section 4.2.8 List of Registers
const enable = enum(u1) {
    disable = 0x0,
    enable = 0x1,
};

const LineControl = packed struct(u32) {
    const parity_type = enum(u1) {
        odd = 0x0,
        even = 0x1,
    };
    const word_length_enum = enum(u2) {
        @"5" = 0x0,
        @"6" = 0x1,
        @"7" = 0x2,
        @"8" = 0x3,
    };
    send_break: u1 = 0,
    parity_enable: enable = .disable,
    even_parity_select: parity_type = .odd,
    two_stop_bits_select: u1 = 0,
    fifo_enable: enable = .disable,
    word_length: word_length_enum = .@"8",
    stick_parity_select: enable = .disable,
    reserved: u24 = 0,
};

const Control = packed struct(u32) {
    uart_enable: enable = .disable,
    sir_enable: enable = .disable,
    sir_low_power: u1 = 0,
    reserved_1: u4 = 0,
    loopback_enable: enable = .disable,
    transmit_enable: enable = .disable,
    receive_enable: enable = .disable,
    data_transmit_ready: u1 = 0,
    request_to_send: u1 = 0,
    out1: u1 = 0,
    out2: u1 = 0,
    rts_flow_control_enable: enable = .disable,
    cts_flow_control_enable: enable = .disable,
    reserved: u16 = 0,
};

const Flags = packed struct(u32) {
    clear_to_send: u1,
    data_set_ready: u1,
    data_carrier_detect: u1,
    busy: bool,
    receive_fifo_empty: bool,
    transmit_fifo_full: bool,
    receive_fifo_full: bool,
    transmit_fifo_empty: bool,
    ring_indicator: u1,
    reserved: u23 = 0,
};

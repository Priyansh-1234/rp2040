const hal = @import("hal");
const gpio = hal.gpio;
const clocks = hal.clocks;

pub fn delay_fn() void {
    for (0..10_000_000) |_| {
        asm volatile ("nop");
    }
}

pub fn main() !void {
    const pin = try gpio.getPin(25);
    pin.set_direction(.out);
    pin.set_function(.sio);

    while (true) {
        pin.toggle_value();
        delay_fn();
    }
}

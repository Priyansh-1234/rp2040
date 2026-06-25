const std = @import("std");
const app = @import("app");
const hal = @import("hal");
const rtos = @import("rtos");

// Linker symbols
extern const _sidata: u32;
extern var _sdata: u32;
extern const _edata: u32;
extern var _sbss: u32;
extern const _ebss: u32;

export fn _start() callconv(.naked) noreturn {
    // Copy data section from flash to RAM
    asm volatile (
        \\  ldr r0, =_sidata
        \\  ldr r1, =_sdata
        \\  ldr r2, =_edata
        \\  b 2f
        \\1:
        \\  ldr r3, [r0]
        \\  str r3, [r1]
        \\  adds r0, r0, #4
        \\  adds r1, r1, #4
        \\2:
        \\  cmp r1, r2
        \\  blo 1b
        \\
        \\  // Zero bss section
        \\  ldr r1, =_sbss
        \\  ldr r2, =_ebss
        \\  movs r3, #0
        \\  b 4f
        \\3:
        \\  str r3, [r1]
        \\  adds r1, r1, #4
        \\4:
        \\  cmp r1, r2
        \\  blo 3b
        \\
        \\  // Call main
        \\  bl _call_main
        \\  // Loop forever if main returns
        \\5:
        \\  b 5b
        \\  .ltorg
    );
}

export fn _call_main() callconv(.c) void {
    if (@hasDecl(hal, "init")) {
        hal.init();
    }

    if (@hasDecl(app, "main")) {
        const typeInfo = @typeInfo(@TypeOf(app.main));
        if (typeInfo == .@"fn") {
            const ReturnType = typeInfo.@"fn".return_type orelse void;
            if (@typeInfo(ReturnType) == .error_union) {
                app.main() catch {};
            } else {
                app.main();
            }
        }
    }
}

// Minimal panic handler to prevent pulling in formatting and printing code from std
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    while (true) {
        asm volatile ("nop");
    }
}

// Vector Table structure
pub const VectorTable = extern struct {
    initial_sp: *const anyopaque,
    reset: *const fn () callconv(.naked) noreturn,
    nmi: ?*const fn () callconv(.c) void = null,
    hard_fault: ?*const fn () callconv(.c) void = null,
    reserved_1: [7]?*const anyopaque = [1]?*const anyopaque{null} ** 7,
    sv_call: ?*const fn () callconv(.c) void = null,
    reserved_2: [2]?*const anyopaque = [1]?*const anyopaque{null} ** 2,
    pend_sv: ?*const fn () callconv(.c) void = null,
    sys_tick: ?*const fn () callconv(.c) void = null,
};

extern const _stack_top: anyopaque;

pub fn default_sys_tick_handler() callconv(.c) void {
    const ptr: *volatile u32 = &hal.systicks.sys_tick_count;
    ptr.* += 1;
}

// Place the vector table in the .vectors section
export const vector_table: VectorTable linksection(".vectors") = .{
    .initial_sp = &_stack_top,
    .reset = _start,
    .sys_tick = default_sys_tick_handler,
    .pend_sv = rtos.scheduler.pend_sv_handler,
};

pub const resets = @import("resets.zig");
pub const xosc = @import("xosc.zig");

/// Initialize the HAL and baseline system components.
/// This resets all non-critical peripheral blocks (using resets.init) and then
/// unresets and waits for those that depend only on the default system/ref clocks (clk_sys and clk_ref).
pub fn init() void {
    // Force reset on all non-critical peripherals to put them in a clean state.
    resets.reset_block(resets.init);

    // Release and wait for peripherals that can operate on the default boot clocks immediately.
    resets.unreset_block_wait(resets.depend_on_sys_ref);
    xosc.init();
}

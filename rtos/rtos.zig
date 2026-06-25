pub const scheduler = @import("scheduler.zig");
pub const exceptions = @import("exceptions.zig");

pub fn init() void {
    // We set the priority of PendSV to the minimum possible
    // priority so that all other exceptions are handled
    // before the PendSv
    exceptions.set_priority(.pendsv, 3);
}

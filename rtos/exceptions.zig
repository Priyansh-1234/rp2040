const PPB_base: u32 = 0xe000_0000;
const Register = @import("hal").register.Register;

const Icsr = packed struct(u32) {
    vect_active: u9,
    reserved_1: u3,
    vect_pending: u9,
    reserved_2: u1,
    isr_pending: u1,
    isr_preempt: u1,
    reserved_3: u1,
    pend_st_clear: u1,
    pend_st_set: u1,
    // Above bit
    // On Write:
    // 0 -> No effect,
    // 1 -> Changes SysTick exception state to pending
    // On Read:
    // 0 -> SysTick exception is not pending
    // 1 -> SysTick exception is pending
    pend_sv_clr: u1,
    pend_sv_set: u1,
    // Above bit
    // On Write:
    // 0 -> No effect,
    // 1 -> Changes PendSV exception state to pending
    // On Read:
    // 0 -> PendSV exception is not pending
    // 1 -> PendSV exception is pending
    reserved_4: u2,
    nmi_pend_set: u1,
    // Write:
    // 0 -> No effect.
    // 1 -> Changes NMI exception state to pending.
    // Read:
    // 0 -> NMI exception is not pending.
    // 1 -> NMI exception is pending.
    // Because NMI is the highest-priority exception, normally the processor enters
    // the NMI
    // exception handler as soon as it detects a write of 1 to this bit. Entering the
    // handler then clears
    // this bit to 0. This means a read of this bit by the NMI exception handler returns
    // 1 only if the
    // NMI signal is reasserted while the processor is executing that handler.
};

const SysHandler3 = packed struct(u32) {
    reserved_1: u22,
    pendsv_priority: u2,
    reserved_2: u6,
    systick_priority: u2,
};

inline fn interrupt_control_status() Register(Icsr) {
    return .{ .address = PPB_base | 0xed04 };
}

inline fn sys_handler3() Register(SysHandler3) {
    return .{ .address = PPB_base | 0xed20 };
}

const Exception = enum {
    systick,
    pendsv,
};

pub inline fn set_priority(exception: Exception, priority: u2) void {
    switch (exception) {
        .systick => sys_handler3().modify(.{ .systick_priority = priority }),
        .pendsv => sys_handler3().modify(.{ .pendsv_priority = priority }),
    }
}

pub inline fn trigger_excpetion(excpetion: Exception) void {
    switch (excpetion) {
        .systick => interrupt_control_status().modify(.{ .pend_st_set = 1 }),
        .pendsv => interrupt_control_status().modify(.{ .pend_sv_set = 1 }),
    }
}

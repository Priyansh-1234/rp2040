const std = @import("std");
const exceptions = @import("exceptions.zig");

pub const State = enum {
    Ready,
    Running,
    Blocked,
    Suspended,
};

pub const Task = extern struct {
    stack_ptr: u32,
    status: State,
    id: u32,
    priority: u8,
};

const MAX_TASKS = 8;

pub const Scheduler = struct {
    tasks: [MAX_TASKS]Task = undefined,
    task_count: usize = 0,
    current_task_idx: ?usize = null,

    pub fn createTask(self: *Scheduler, stack: []u32, entry: fn () void, priority: u8) !void {
        if (self.task_count >= MAX_TASKS) return error.MaxTasksReached;

        const sp = initStack(stack, entry);
        self.tasks[self.task_count] = .{
            .stack_ptr = sp,
            .status = .Ready,
            .id = @intCast(self.task_count),
            .priority = priority,
        };
        self.task_count += 1;
    }

    pub fn selectNextTask(self: *Scheduler) void {
        if (self.task_count == 0) return;

        // Simple Round-Robin Scheduler
        const start_idx = if (self.current_task_idx) |curr| (curr + 1) % self.task_count else 0;
        var idx = start_idx;

        while (true) {
            if (self.tasks[idx].status == .Ready or self.tasks[idx].status == .Running) {
                if (self.current_task_idx) |curr| {
                    if (self.tasks[curr].status == .Running) {
                        self.tasks[curr].status = .Ready;
                    }
                }
                self.tasks[idx].status = .Running;
                self.current_task_idx = idx;
                return;
            }
            idx = (idx + 1) % self.task_count;
            if (idx == start_idx) break;
        }
    }

    pub fn start(self: *Scheduler) void {
        if (self.task_count == 0) return;
        self.current_task_idx = 0;
        self.tasks[0].status = .Running;
        current_task_sp = self.tasks[0].stack_ptr;

        // Initialize PSP to 0 so the PendSV handler knows this is the first context switch
        asm volatile ("msr psp, %[psp]" : : [psp] "r" (@as(u32, 0)));

        // Trigger PendSV by writing to ICSR (Interrupt Control and State Register)
        exceptions.trigger_excpetion(.pendsv);

        // Enable interrupts globally
        asm volatile ("cpsie i");
        
        // Sleep until the PendSV interrupt fires and context switches us to the first task
        while (true) {
            asm volatile ("wfi");
        }
    }
};

fn initStack(stack: []u32, entry: fn () void) u32 {
    const len = stack.len;
    // We need 16 words for the stack context frame
    const sp_index = len - 16;

    // --- Hardware Frame ---
    stack[sp_index + 15] = 0x0100_0000;                // xPSR (T bit set for Thumb mode)
    stack[sp_index + 14] = @intFromPtr(entry);         // PC (Task Entry point)
    stack[sp_index + 13] = @intFromPtr(taskExitError); // LR (Return handler)
    stack[sp_index + 12] = 0;                          // R12
    stack[sp_index + 11] = 0;                          // R3
    stack[sp_index + 10] = 0;                          // R2
    stack[sp_index + 9]  = 0;                          // R1
    stack[sp_index + 8]  = 0;                          // R0 (Parameter)

    // --- Software Frame ---
    stack[sp_index + 7] = 0;                           // R7
    stack[sp_index + 6] = 0;                           // R6
    stack[sp_index + 5] = 0;                           // R5
    stack[sp_index + 4] = 0;                           // R4
    stack[sp_index + 3] = 0;                           // R11
    stack[sp_index + 2] = 0;                           // R10
    stack[sp_index + 1] = 0;                           // R9
    stack[sp_index + 0] = 0;                           // R8

    return @intFromPtr(&stack[sp_index]);
}

fn taskExitError() callconv(.c) void {
    while (true) {
        asm volatile ("nop");
    }
}

pub var os_scheduler = Scheduler{};
export var current_task_sp: u32 = 0;

export fn switchTask() callconv(.c) void {
    if (os_scheduler.current_task_idx) |curr| {
        os_scheduler.tasks[curr].stack_ptr = current_task_sp;
    }

    os_scheduler.selectNextTask();

    if (os_scheduler.current_task_idx) |curr| {
        current_task_sp = os_scheduler.tasks[curr].stack_ptr;
    }
}

pub export fn pend_sv_handler() callconv(.naked) void {
    asm volatile (
        \\  mrs r0, psp
        \\
        \\  // If PSP is 0, we are executing the very first context switch.
        \\  // Skip saving the current context because there is no task running yet!
        \\  cmp r0, #0
        \\  beq restore_context
        \\
        \\  // Make space for R4-R11 (8 registers = 32 bytes)
        \\  subs r0, r0, #32
        \\
        \\  // Save low registers R4-R7
        \\  adds r1, r0, #16
        \\  stmia r1!, {r4-r7}
        \\
        \\  // Save high registers R8-R11 by moving them to low registers first
        \\  mov r4, r8
        \\  mov r5, r9
        \\  mov r6, r10
        \\  mov r7, r11
        \\  stmia r0!, {r4-r7}
        \\
        \\  // Move r0 back to the base of our software stack frame
        \\  subs r0, r0, #16
        \\
        \\  // Store the updated PSP into the global current_task_sp variable
        \\  ldr r1, =current_task_sp
        \\  str r0, [r1]
        \\
        \\  // Call the Zig function to select the next task.
        \\  // We MUST push LR to the Main Stack before bl to preserve EXC_RETURN!
        \\  push {lr}
        \\  bl switchTask
        \\  pop {r2}
        \\  mov lr, r2
        \\
        \\restore_context:
        \\  // Load the new stack pointer from current_task_sp
        \\  ldr r1, =current_task_sp
        \\  ldr r0, [r1]
        \\
        \\  // Restore high registers R8-R11
        \\  ldmia r0!, {r4-r7}
        \\  mov r8, r4
        \\  mov r9, r5
        \\  mov r10, r6
        \\  mov r11, r7
        \\
        \\  // Restore low registers R4-R7
        \\  ldmia r0!, {r4-r7}
        \\
        \\  // Update PSP to point to the hardware frame
        \\  msr psp, r0
        \\
        \\  // Force hardware to return to Thread mode using PSP
        \\  ldr r0, =0xFFFFFFFD
        \\  bx r0
        \\  .ltorg
    );
}

# Agent Context, Guidelines, and Memory

This file serves as the persistent memory, identity configuration, and rulebook for AI assistants (like Antigravity) working on this project. 

> [!IMPORTANT]
> AI agents must read this file at the start of every session to align with the role, guidelines, and current project architecture.

---

## 1. Agent Role & Guidelines

### The Teacher Persona
*   **Guide, Don't Code:** You act as a **teacher and guide** rather than a keyboard programmer. Your primary responsibility is to explain the "how" and "why" behind the code, walk through concepts, and suggest abstractions.
*   **Do Not Implement Code Directly:** Do not write code files or make modifications to existing files unless the user **explicitly asks you to write code** (e.g., "Implement this function," "Write the code for..."). Focus on providing clear explanations, algorithms, and code snippets in the chat for the user to learn from.
*   **Pedagogical Tone:** Maintain an informative, patient, and educational tone. Break complex embedded concepts down into understandable components.

### Reference Rules (Datasheet Citations)
*   **Cite the Datasheet:** Whenever you use information regarding the RP2040 hardware (registers, memory-mapped offsets, peripherals, timings, etc.), you **must specify the exact sections** of the official *RP2040 Datasheet* where you retrieved that information.
*   *Example:* "According to the RP2040 Datasheet, Section 2.19.2 (GPIO Control Registers), the GPIO control registers start at offset..."

---

## 2. Project Context
*   **Objective:** An attempt to write a custom Hardware Abstraction Layer (HAL) and a simple Real-Time Operating System (RTOS) from scratch for the RP2040.
*   **Target Hardware:** Raspberry Pi Pico (RP2040 microcontroller with dual ARM Cortex-M0+ cores).
*   **Languages:** Zig (version `0.16.0`) and ARM Thumb Assembly.
*   **Environment:** Freestanding, bare-metal (no standard OS or C library dependency).

---

## 3. Current Directory Structure & Project State

Below is the layout of the project workspace:

*   [build.zig](file:///home/priyansh/projects/rp2040/build.zig) - The build orchestration script.
*   [bootloader/](file:///home/priyansh/projects/rp2040/bootloader)
    *   [boot2.S](file:///home/priyansh/projects/rp2040/bootloader/boot2.S) - Second-stage bootloader assembly.
    *   [linker.ld](file:///home/priyansh/projects/rp2040/bootloader/linker.ld) - Linker script for RAM and Flash memory mapping.
    *   [startup.zig](file:///home/priyansh/projects/rp2040/bootloader/startup.zig) - Startup execution, BSS zeroing, main vector table configuration, and HAL early initialization.
*   [hal/](file:///home/priyansh/projects/rp2040/hal)
    *   [hal.zig](file:///home/priyansh/projects/rp2040/hal/hal.zig) - Main HAL namespace and system initialization launcher.
    *   [register.zig](file:///home/priyansh/projects/rp2040/hal/register.zig) - Generic register wrapper abstraction providing `.read()`, `.write()`, and `.modify()` helpers.
    *   [resets.zig](file:///home/priyansh/projects/rp2040/hal/resets.zig) - Subsystem Resets controller driver using enum-based offsets and atomic set/clear registers.
    *   [xosc.zig](file:///home/priyansh/projects/rp2040/hal/xosc.zig) - External Crystal Oscillator (XOSC) configuration using RMW packed register structures.
    *   [pll.zig](file:///home/priyansh/projects/rp2040/hal/pll.zig) - Phase-Locked Loop (PLL) configuration layout.
*   [src/](file:///home/priyansh/projects/rp2040/src)
    *   [main.zig](file:///home/priyansh/projects/rp2040/src/main.zig) - Application entry point.
*   [tools/](file:///home/priyansh/projects/rp2040/tools)
    *   [elf2uf2.zig](file:///home/priyansh/projects/rp2040/tools/elf2uf2.zig) - Custom host utility for checksum calculations and UF2 file formatting.

### Analysis of Existing Components

#### A. Build System (`build.zig`)
*   Targets the `thumb-cortex_m0plus-freestanding-eabi` triple.
*   Compiles `tools/elf2uf2.zig` as a native host executable to generate the UF2 image helper.
*   Defines a module named `"hal"` mapped to `hal/hal.zig`.
*   Adds the `"hal"` module as an import to both the user application (`app_module`) and the reset startup driver (`startup_module`), allowing clean `@import("hal")` usage.
*   Produces a raw binary representation (`firmware.bin`) which is then passed to `elf2uf2` to compute the boot2 checksum, prepend UF2 headers, and output `firmware.uf2`.

#### B. Second-Stage Bootloader (`bootloader/boot2.S`)
*   Assumes flash execution starts in a 256-byte block at `0x10000000` (RP2040 ROM bootloader load address).
*   Configures the Synchronous Serial Interface (SSI) peripheral at base `0x18000000` to execute directly from flash (XIP mode).
*   Calculates a checksum over the first 252 bytes and writes it to the final 4 bytes of the sector (handled by `tools/elf2uf2.zig`).
*   Configures the Vector Table Offset Register (VTOR) to point to the main vector table at `0x10000100` and jumps to the reset handler.

#### C. Startup Setup (`bootloader/startup.zig`)
*   Declares the raw `_start` entry point under the naked calling convention.
*   Runs inline assembly to copy `.data` from Flash to RAM and zero out `.bss`.
*   Invokes `hal.init()` to initialize peripheral reset states before calling `app.main()`.
*   Defines the main `VectorTable` structure and links it to `.vectors`.

#### D. Linker Layout (`bootloader/linker.ld`)
*   Splits memory into:
    *   `FLASH`: 2048 KB starting at `0x10000000`.
    *   `RAM`: 256 KB starting at `0x20000000`.
*   Puts `.boot2` at the very front of FLASH.
*   Aligns `.vectors` and `.text` inside FLASH.
*   Sets `_stack_top` at the absolute top of RAM (`0x20040000`).

---

## 4. Agent Memory & State Tracker

This section serves as a history log of what has been accomplished, design decisions, and unresolved tasks.

### Active Decisions Log
*   **Linker Stack Placement:** The stack top (`_stack_top`) is currently placed at `0x20040000`. In a multi-tasking context (RTOS), this will act as the Main Stack Pointer (MSP) for interrupts and scheduler execution, while each thread will use a separate Process Stack Pointer (PSP) pointing to an aligned block in RAM.
*   **Modular HAL Structure:** Configured `hal` as a named build module in `build.zig`. This allows other files to import it cleanly as `@import("hal")` instead of using relative paths (e.g. `../hal/hal.zig`), which triggers compiler boundaries errors in freestanding EABI builds.
*   **Atomic Register Access (Resets):** Implemented write-modifying aliases for resets (`ALIAS_SET` and `ALIAS_CLR` representing address offsets `0x2000` and `0x3000` respectively) to prevent read-modify-write CPU races.
*   **Register Wrapper API Pattern:** Designed and implemented a lightweight generic `Register(T)` wrapper (in `hal/register.zig`) to handle clean type-safe hardware register access with `.read()`, `.write()`, and `.modify()` methods. This replaces raw struct fields directly mapped to pointer dereferences and optimizes away compile-time fields with zero runtime overhead.
*   **Refactored XOSC Initialization:** Ported the XOSC driver to use the new `Register` wrapper API, and resolved a bug in XOSC enablement by setting `.enable = .enable` (`0xfab`) to prevent boot hangs.
*   **Clean and Type-Safe PLL Driver:** Ported the PLL driver using the new `Register` wrapper, incorporating compile-time asserts (`comptime` check block) to validate feedback/post-divider bounds, loop design rules, and minimum reference frequencies based on RP2040 Datasheet constraints (Section 2.18.2).

### Backlog & Next Steps
1.  **Clock Tree Routing:** Connect XOSC and PLL outputs to `clk_sys` and `clk_ref` (handling safe fallback switches away from auxiliary clocks), scaling the system clock to 125 MHz.
2.  **GPIO / SIO Driver:** Build pin configuration (FSEL settings) and single-cycle IO control (GPIO reads, writes, atomic toggle).
3.  **SysTick Setup:** Guide the initialization of the ARM Cortex-M0+ SysTick timer to drive scheduling ticks.
4.  **Context Switching Mechanics:** Outline the PendSV exception handler structure in Zig/Assembly to swap task registers.
5.  **Task TCB Design:** Draft the Task Control Block (TCB) structures.

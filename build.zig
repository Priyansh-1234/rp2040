const std = @import("std");

pub fn build(b: *std.Build) void {

    // The "elf2uf2" here is a misnomer actually since
    // I convert a bin file into a uf2 file and not a
    // elf file to uf2 file.
    // This file will be installed and excuted on the host
    // machine that is why the target is set to the host.
    const elf2uf2 = b.addExecutable(.{
        .name = "elf2uf2",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/elf2uf2.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    b.installArtifact(elf2uf2);

    // Here we define the target architecture for the
    // RP2040
    const target_query = std.Target.Query{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
        .os_tag = .freestanding,
        .abi = .eabi,
    };
    const target = b.resolveTargetQuery(target_query);

    // Create the HAL module so it can be imported anywhere in the project
    const hal_module = b.createModule(.{
        .root_source_file = b.path("hal/hal.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });

    const rtos_module = b.createModule(.{
        .root_source_file = b.path("rtos/rtos.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "hal", .module = hal_module },
        },
    });

    // The user can create the files in the src/main.zig file
    // and the start of their code is the main function.
    // Currently the main function can't take the init parameter
    const app_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "hal", .module = hal_module },
            .{ .name = "rtos", .module = rtos_module },
        },
    });

    // This is the actual entry point of the code
    const startup_module = b.createModule(.{
        .root_source_file = b.path("bootloader/startup.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "app", .module = app_module },
            .{ .name = "hal", .module = hal_module },
            .{ .name = "rtos", .module = rtos_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "firmware",
        .root_module = startup_module,
    });

    // Set all the appropriate linker options and
    // add the boot2.S file
    exe.setLinkerScript(b.path("bootloader/linker.ld"));
    exe.root_module.addAssemblyFile(b.path("bootloader/boot2.S"));
    exe.entry = .{ .symbol_name = "_start" };
    exe.build_id = .none;

    // Get the binary in bin format from an elf file which
    // we will convert into a uf2 file using the elf2uf2 file.
    const bin = b.addObjCopy(exe.getEmittedBin(), .{
        .basename = "firmware.bin",
        .format = .bin,
    });

    // Run elf2uf2 to convert .bin to .uf2
    const run_elf2uf2 = b.addRunArtifact(elf2uf2);
    run_elf2uf2.addFileArg(bin.getOutput());
    const uf2_out = run_elf2uf2.addOutputFileArg("firmware.uf2");

    // Install the .uf2 file
    const install_uf2 = b.addInstallFileWithDir(uf2_out, .{ .custom = "bin" }, "firmware.uf2");

    const install_step = b.step("uf2", "Build and install the UF2 firmware");
    install_step.dependOn(&install_uf2.step);

    b.getInstallStep().dependOn(&install_uf2.step);
}

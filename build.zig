const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a shared library module for all HolyCross code
    const holycross_lib = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main compiler executable
    const exe = b.addExecutable(.{
        .name = "hcc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    // Preprocessor executable
    const hcpp = b.addExecutable(.{
        .name = "hcpp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/hcpp.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hcpp.root_module.addImport("holycross", holycross_lib);

    b.installArtifact(hcpp);

    // Assembler executable
    const hcas = b.addExecutable(.{
        .name = "hcas",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/hcas.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hcas.root_module.addImport("holycross", holycross_lib);

    b.installArtifact(hcas);

    const run_step = b.step("run", "Run the HolyC compiler");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_hcpp_step = b.step("run-hcpp", "Run the HolyC preprocessor");
    const run_hcpp_cmd = b.addRunArtifact(hcpp);
    run_hcpp_step.dependOn(&run_hcpp_cmd.step);
    run_hcpp_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args_pp| {
        run_hcpp_cmd.addArgs(args_pp);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);

    const fmt_step = b.step("fmt", "Format all source files");
    const fmt = b.addFmt(.{
        .paths = &.{ "src", "build.zig" },
        .check = false,
    });
    fmt_step.dependOn(&fmt.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const reporter_module = b.createModule(.{
        .root_source_file = b.path("src/reporter.zig"),
        .target = target,
        .optimize = optimize,
    });

    // const servermock_module = b.createModule(.{
    //     .root_source_file = b.path("src/servermock.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/reporter_cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const reporter = b.addLibrary(.{
        .name = "greener_reporter",
        .root_module = reporter_module,
        .linkage = .dynamic,
    });
    reporter.linkLibC();
    b.installArtifact(reporter);

    const reporter_static = b.addLibrary(.{
        .name = "greener_reporter",
        .root_module = reporter_module,
        .linkage = .static,
    });
    reporter_static.linkLibC();
    b.installArtifact(reporter_static);

    // const servermock = b.addLibrary(.{
    //     .name = "greener_servermock",
    //     .root_module = servermock_module,
    //     .linkage = .dynamic,
    // });
    // b.installArtifact(servermock);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = test_module,
    });
    tests.linkLibrary(reporter);
    // tests.linkLibrary(servermock);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);

    const cli = b.addExecutable(.{
        .name = "reporter-cli",
        .root_module = cli_module,
    });
    cli.linkLibrary(reporter_static);
    b.installArtifact(cli);
}

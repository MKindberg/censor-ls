const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "censor-ls",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    var cwd = std.fs.cwd().openDir("src", .{ .iterate = true }) catch unreachable;
    defer cwd.close();
    var walker = cwd.walk(b.allocator) catch unreachable;
    defer walker.deinit();

    const test_step = b.step("test", "Run unit tests");
    while (walker.next() catch unreachable) |entry| {
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        const tests = b.addTest(.{
            .root_source_file = b.path(b.fmt("src/{s}", .{entry.path})),
            .target = target,
            .optimize = optimize,
        });
        const run_tests = b.addRunArtifact(tests);
        test_step.dependOn(&run_tests.step);
    }
    const registry_generator = b.addExecutable(.{
        .name = "generate_registry",
        .root_source_file = b.path("tools/mason_registry.zig"),
        .target = b.host,
    });
    const registry_step = b.step("gen_registry", "Generate mason.nvim registry");
    const registry_generation = b.addRunArtifact(registry_generator);
    registry_step.dependOn(&registry_generation.step);


}

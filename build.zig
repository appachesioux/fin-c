const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);
    options.addOption([]const u8, "app_name", "fin-c");

    // raylib-zig dependency
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib_artifact = raylib_dep.artifact("raylib");

    // Zig modules
    const raylib_module = raylib_dep.module("raylib");
    const raygui_module = raylib_dep.module("raygui");

    const exe = b.addExecutable(.{
        .name = "fin-c",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "build_options", .module = options.createModule() },
                .{ .name = "raylib", .module = raylib_module },
                .{ .name = "raygui", .module = raygui_module },
            },
        }),
    });

    exe.linkLibC();
    exe.root_module.linkLibrary(raylib_artifact);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run fin-c");
    run_step.dependOn(&run_cmd.step);
}

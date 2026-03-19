const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gui = b.option([]const u8, "gui", "Frontend: \"gtk\" (default) or \"raylib\"") orelse "gtk";
    const use_gtk = std.mem.eql(u8, gui, "gtk");

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);
    options.addOption([]const u8, "app_name", "fin-c");

    const root_source = if (use_gtk) b.path("src/main_gtk.zig") else b.path("src/main.zig");

    const exe = b.addExecutable(.{
        .name = "fin-c",
        .root_module = b.createModule(.{
            .root_source_file = root_source,
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "build_options", .module = options.createModule() },
            },
        }),
    });

    exe.linkLibC();

    if (use_gtk) {
        exe.linkSystemLibrary("gtk4");
    } else {
        const raylib_dep = b.dependency("raylib_zig", .{
            .target = target,
            .optimize = optimize,
        });
        const raylib_artifact = raylib_dep.artifact("raylib");
        exe.root_module.linkLibrary(raylib_artifact);
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run fin-c");
    run_step.dependOn(&run_cmd.step);
}

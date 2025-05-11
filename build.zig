const std = @import("std");
pub fn build(b: *std.Build) !void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),

        // this is the target for the Book and my machine.
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .macos,
        }),
        .optimize = switch (b.release_mode) {
            .off => .Debug,
            .safe => .ReleaseSafe,
            else => .ReleaseFast,
        },
    });

    const exe = b.addExecutable(.{
        .name = "paella",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    { // `zig build run` command
        const run_step = b.step("run", "Run the app");

        const run_cmd = b.addRunArtifact(exe);
        if (b.args) |args| // pass aruments into `zig build run --`
            run_cmd.addArgs(args);

        run_cmd.step.dependOn(b.getInstallStep());
        run_step.dependOn(&run_cmd.step);
    }

    { // `zig build test` command
        const test_step = b.step("test", "Run tests");

        // subshells. how do they work.
        const inner_command = try std.mem.join(b.allocator, " ", &.{
            "../writing-a-c-compiler-tests/test_compiler",
            b.pathJoin(&.{ b.exe_dir, "paella" }),
            try std.mem.join(
                b.allocator,
                " ",
                b.args orelse &.{""},
            ),
        });

        // does this work like i think it does?
        const test_command = b.addSystemCommand(
            &.{ "arch", "-x86_64", "zsh", "-c", inner_command },
        );

        test_command.step.dependOn(b.getInstallStep());
        test_step.dependOn(&test_command.step);
    }
}

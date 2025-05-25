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

    const fmt_step = b.addFmt(.{ .paths = &.{"./"} });
    exe.step.dependOn(&fmt_step.step);

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
        const test_step = b.step("test", "Run unit tests");

        const exe_unit_tests = b.addTest(.{
            .root_module = exe_mod,
        });
        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

        test_step.dependOn(&run_exe_unit_tests.step);
    }

    { // `zig build submit` command
        const test_step = b.step("submit", "Run the Book's test suite");
        const all_tests = b.option(bool, "all", "run all tests in submit") orelse false;

        // subshells. how do they work.
        const inner_command = try std.mem.join(b.allocator, " ", &.{
            "../writing-a-c-compiler-tests/test_compiler",
            b.pathJoin(&.{ b.exe_dir, "paella" }),
            try std.mem.join(
                b.allocator,
                " ",
                b.args orelse &.{},
            ),
            if (all_tests) "" else "--latest-only",
        });

        // does this work like i think it does?
        const test_command = b.addSystemCommand(
            &.{ "arch", "-x86_64", "zsh", "-c", inner_command },
        );

        test_command.step.dependOn(b.getInstallStep());
        test_step.dependOn(&test_command.step);
    }

    { // `zig build eye` command
        const eye_step = b.step("eye", "Eye test all the files in a given directory");

        if (b.option(std.Build.LazyPath, "folder", "Path to eye")) |lazy|
            try walk_tree(b, exe, eye_step, lazy)
        else
            eye_step.dependOn(&b.addFail("folder needed for eye").step);
    }
}

fn walk_tree(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    eye_step: *std.Build.Step,
    lazy: std.Build.LazyPath,
) !void {
    const path = lazy.getPath3(b, null);
    const dir = try path.openDir("", .{ .iterate = true });
    var walker = dir.iterate();

    var prev_run_cmd: ?*std.Build.Step.Run = null;
    while (try walker.next()) |entry| if (entry.kind == .file and
        std.mem.endsWith(u8, entry.name, ".c"))
    {
        const file = entry.name;

        const bat = b.addSystemCommand(&.{ "bat", file });
        bat.addArg("--paging=never");
        bat.setCwd(lazy);
        bat.stdio = .inherit;

        if (prev_run_cmd) |c|
            bat.step.dependOn(&c.step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.setCwd(lazy);
        run_cmd.addArg(file);
        run_cmd.addArgs(b.args orelse &.{});
        run_cmd.stdio = .inherit;

        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.step.dependOn(&bat.step);

        prev_run_cmd = run_cmd;
    };

    eye_step.dependOn(&prev_run_cmd.?.step);
}

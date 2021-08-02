const std = @import("std");
const pkgs = @import(".zpm/pkgs.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("positron-demo", "example/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    linkPositron(exe);
    exe.install();

    const positron_test = b.addTest("src/positron.zig");
    linkPositron(positron_test);

    const test_step = b.step("test", "Runs the test suite");
    test_step.dependOn(&positron_test.step);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn linkPositron(exe: *std.build.LibExeObjStep) void {
    exe.linkLibC();
    exe.linkSystemLibrary("c++");
    exe.addPackage(pkgs.pkgs.positron);
    exe.addCSourceFile("src/binding.cpp", &[_][]const u8{
        "-std=c++11",
    });
    exe.addIncludeDir("vendor/webview");

    switch (exe.target.getOsTag()) {
        //# Windows (x64)
        //$ c++ main.cc -mwindows -L./dll/x64 -lwebview -lWebView2Loader -o webview-example.exe
        .windows => {
            exe.addLibPath("vendor/webview/dll/x64");
        },
        //# MacOS
        //$ c++ main.cc -std=c++11 -framework WebKit -o webview-example
        .macos => {
            exe.linkFramework("WebKit");
        },
        //# Linux
        //$ c++ main.cc `pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.0` -o webview-example
        .linux => {
            exe.linkSystemLibrary("gtk+-3.0");
            exe.linkSystemLibrary("webkit2gtk-4.0");
        },
        else => std.debug.panic("unsupported os: {s}", .{std.meta.tagName(exe.target.getOsTag())}),
    }
}

const std = @import("std");
const pkgs = @import(".zpm/pkgs.zig");
const Sdk = @import("Sdk.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const backend = b.option(Sdk.Backend, "backend", "Configures the backend that should be used for webview.");

    const exe = b.addExecutable("positron-demo", "example/main.zig");

    exe.setTarget(target);

    exe.setBuildMode(mode);

    Sdk.linkPositron(exe, backend);
    exe.addPackage(Sdk.getPackage("positron"));

    exe.install();

    const positron_test = b.addTest("src/positron.zig");

    Sdk.linkPositron(positron_test, null);
    positron_test.addPackage(Sdk.getPackage("positron"));

    const test_step = b.step("test", "Runs the test suite");

    test_step.dependOn(&positron_test.step);

    const run_cmd = exe.run();

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");

    run_step.dependOn(&run_cmd.step);

    // const demo = b.addExecutable("webview-demo", null);

    // // make webview library standalone
    // demo.addCSourceFile("src/minimal.cpp", &[_][]const u8{
    //     "-std=c++17",
    //     "-fno-sanitize=undefined",
    // });
    // demo.linkLibC();
    // demo.linkSystemLibrary("c++");
    // demo.install();

    // demo.addIncludeDir("vendor/Microsoft.Web.WebView2.1.0.902.49/build/native/include");
    // demo.addLibPath("vendor/Microsoft.Web.WebView2.1.0.902.49/build/native/x64");
    // demo.linkSystemLibrary("user32");
    // demo.linkSystemLibrary("ole32");
    // demo.linkSystemLibrary("oleaut32");
    // demo.addObjectFile("vendor/Microsoft.Web.WebView2.1.0.902.49/build/native/x64/WebView2Loader.dll.lib");

    // const exec = demo.run();
    // exec.step.dependOn(b.getInstallStep());

    // const demo_run_step = b.step("run.demo", "Run the app");
    // demo_run_step.dependOn(&exec.step);
}

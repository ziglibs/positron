const std = @import("std");
const pkgs = @import(".zpm/pkgs.zig");

const Backend = enum {
    gtk,
    cocoa,
    edge,
};

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const backend = b.option(Backend, "backend", "Configures the backend that should be used for webview.");

    const exe = b.addExecutable("positron-demo", "example/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    linkPositron(exe, backend);
    exe.install();

    const positron_test = b.addTest("src/positron.zig");
    linkPositron(positron_test, null);

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

fn linkPositron(exe: *std.build.LibExeObjStep, backend: ?Backend) void {
    exe.linkLibC();
    exe.linkSystemLibrary("c++");
    exe.addPackage(pkgs.pkgs.positron);

    // make webview library standalone
    exe.addCSourceFile("src/wv/webview.cpp", &[_][]const u8{
        "-std=c++17",
        "-fno-sanitize=undefined",
    });

    if (exe.target.isWindows()) {

        // Attempts to fix windows building:
        exe.addIncludeDir("vendor/winsdk");

        exe.addIncludeDir("vendor/Microsoft.Web.WebView2.1.0.902.49/build/native/include");
        exe.addLibPath("vendor/Microsoft.Web.WebView2.1.0.902.49/build/native/x64");
        exe.linkSystemLibrary("ole32");
        exe.linkSystemLibrary("oleaut32");
        exe.addObjectFile("vendor/Microsoft.Web.WebView2.1.0.902.49/build/native/x64/WebView2Loader.dll.lib");
        //exe.linkSystemLibrary("windowsapp");
    }

    if (backend) |b| {
        switch (b) {
            .gtk => exe.defineCMacro("WEBVIEW_GTK", null),
            .cocoa => exe.defineCMacro("WEBVIEW_COCOA", null),
            .edge => exe.defineCMacro("WEBVIEW_EDGE", null),
        }
    }

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

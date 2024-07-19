const std = @import("std");

pub const Backend = enum {
    gtk,
    cocoa,
    edge,
};

fn sdkRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn getPackage(name: []const u8) std.build.Pkg {
    const sdkPath = comptime sdkRoot();
    return std.build.Pkg{
        .name = name,
        .source = .{ .path = sdkPath ++ "/src/positron.zig" },
        .dependencies = &[_]std.build.Pkg{
            std.build.Pkg{
                .name = "serve",
                .source = .{ .path = sdkPath ++ "/vendor/serve/src/serve.zig" },
                .dependencies = &[_]std.build.Pkg{
                    std.build.Pkg{
                        .name = "uri",
                        .source = .{ .path = sdkPath ++ "/vendor/serve/vendor/uri/uri.zig" },
                    },
                    std.build.Pkg{
                        .name = "network",
                        .source = .{ .path = sdkPath ++ "/vendor/serve/vendor/network/network.zig" },
                    },
                },
            },
        },
    };
}

/// Links positron to `exe`. `exe` must have its final `target` already set!
/// `backend` selects the backend to be used, use `null` for a good default.
pub fn linkPositron(exe: *std.build.LibExeObjStep, backend: ?Backend) void {
    exe.linkLibC();
    exe.linkSystemLibrary("c++");

    // make webview library standalone
    const sdkPath = comptime sdkRoot();
    exe.addCSourceFile(sdkPath ++ "/src/wv/webview.cpp", &[_][]const u8{
        "-std=c++17",
        "-fno-sanitize=undefined",
    });

    if (exe.target.isWindows()) {

        // Attempts to fix windows building:
        exe.addIncludePath("vendor/winsdk");

        exe.addIncludePath(sdkPath ++ "/vendor/Microsoft.Web.WebView2.1.0.902.49/build/native/include");
        exe.addLibraryPath(sdkPath ++ "/vendor/Microsoft.Web.WebView2.1.0.902.49/build/native/x64");
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("ole32");
        exe.linkSystemLibrary("oleaut32");
        exe.addObjectFile(sdkPath ++ "/vendor/Microsoft.Web.WebView2.1.0.902.49/build/native/x64/WebView2Loader.dll.lib");
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
            exe.addLibraryPath(sdkPath ++ "/vendor/webview/dll/x64");
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

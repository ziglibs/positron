const std = @import("std");

fn pkgRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub const pkgs = struct {
    pub const args = std.build.Pkg{
        .name = "args",
        .path = .{ .path = pkgRoot() ++ "/../vendor/args/args.zig" },
        .dependencies = &[_]std.build.Pkg{},
    };
    pub const apple_pie = std.build.Pkg{
        .name = "apple_pie",
        .path = .{ .path = pkgRoot() ++ "/../.zpm/../vendor/apple_pie/src/apple_pie.zig" },
        .dependencies = &[_]std.build.Pkg{},
    };
    pub const positron = std.build.Pkg{
        .name = "positron",
        .path = .{ .path = pkgRoot() ++ "/../.zpm/../src/positron.zig" },
        .dependencies = &[_]std.build.Pkg{apple_pie},
    };
};

pub const imports = struct {
};

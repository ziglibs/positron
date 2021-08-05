const std = @import("std");
const wv = @import("positron");

pub fn main() !void {
    const view = try wv.View.create(false, null);
    defer view.destroy();

    view.setTitle("Webview Example");
    view.setSize(480, 320, .none);

    view.navigate("https://ziglang.org");
    view.run();
}

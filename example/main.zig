const std = @import("std");
const wv = @import("positron");

pub fn main() !void {
    const view = try wv.WebView.create(false, null);
    defer view.destroy();

    view.setTitle("Webview Example");
    view.setSize(480, 320, .none);

    view.bind("sayHello", view, sayHello);

    view.init(
        \\document.addEventListener("DOMContentLoaded", () => {
        \\  const overlay = document.createElement("div");
        \\  overlay.innerText = "Hello, Ziguanas!";
        \\  overlay.style.display = "block";
        \\  overlay.style.position = "fixed";
        \\  overlay.style.left = 0;
        \\  overlay.style.top = 0;
        \\  overlay.style.backgroundColor = "white";
        \\  overlay.style.padding = "10px";
        \\  overlay.style.zIndex = 100;
        \\  overlay.addEventListener("click", () => {
        \\    overlay.style.backgroundColor = "blue";
        \\    sayHello();
        \\    overlay.style.backgroundColor = "red";
        \\  });
        \\  document.body.appendChild(overlay);
        \\});
    );

    view.navigate("https://ziglang.org");
    view.run();
}

fn sayHello(view: *wv.WebView, seq: [:0]const u8, req: [:0]const u8) void {
    std.debug.print("sayHello('{s}', '{s}')\n", .{
        seq, req,
    });
    view.@"return"(seq, .{ .success = "{}" });
}

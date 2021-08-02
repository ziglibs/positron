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
        \\    overlay.innerText = "running";
        \\    sayHello({ x: 1, y: 2 }, "hello", 42.0).then((v) => { overlay.innerText = "success:" + JSON.stringify(v); overlay.style.backgroundColor = "green"; }).catch((v) => { overlay.innerText = "error:" + JSON.stringify(v); overlay.style.backgroundColor = "red"; });
        \\  });
        \\  document.body.appendChild(overlay);
        \\});
    );

    view.navigate("https://ziglang.org");
    view.run();
}

const Point = struct {
    x: f32,
    y: f32,
};

var calls: usize = 0;
fn sayHello(view: *wv.WebView, pt: Point, text: []const u8, value: f64) !u32 {
    _ = view;
    std.debug.print("sayHello({}, \"{s}\", {d})\n", .{ pt, text, value });

    if (calls > 3)
        return error.TooManyCalls;
    calls += 1;

    return @truncate(u32, calls);
}

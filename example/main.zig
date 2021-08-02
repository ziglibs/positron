const std = @import("std");
const wv = @import("positron");

const App = struct {
    provider: *wv.Provider,
    view: *wv.View,

    pub fn getWebView(app: *App) *wv.View {
        return app.view;
    }
};

pub fn main() !void {
    var app = App{
        .provider = undefined,
        .view = undefined,
    };

    app.provider = try wv.Provider.create(std.heap.c_allocator);
    defer app.provider.destroy();

    std.log.info("base uri: {s}", .{app.provider.base_url});

    try app.provider.addContent("/login.htm", "text/html", @embedFile("login.htm"));
    try app.provider.addContent("/app.htm", "text/html", @embedFile("app.htm"));

    const thread = try std.Thread.spawn(.{}, wv.Provider.run, .{app.provider});
    thread.detach();

    app.view = try wv.View.create((std.builtin.mode == .Debug), null);
    defer app.view.destroy();

    app.view.setTitle("Webview Example");
    app.view.setSize(400, 550, .fixed);

    app.view.bind("performLogin", performLogin, &app);

    // view.init(
    //     \\document.addEventListener("DOMContentLoaded", () => {
    //     \\  const overlay = document.createElement("div");
    //     \\  overlay.innerText = "Hello, Ziguanas!";
    //     \\  overlay.style.display = "block";
    //     \\  overlay.style.position = "fixed";
    //     \\  overlay.style.left = 0;
    //     \\  overlay.style.top = 0;
    //     \\  overlay.style.backgroundColor = "white";
    //     \\  overlay.style.padding = "10px";
    //     \\  overlay.style.zIndex = 100;
    //     \\  overlay.addEventListener("click", () => {
    //     \\    overlay.style.backgroundColor = "blue";
    //     \\    overlay.innerText = "running";
    //     \\    sayHello({ x: 1, y: 2 }, "hello", 42.0).then((v) => { overlay.innerText = "success:" + JSON.stringify(v); overlay.style.backgroundColor = "green"; }).catch((v) => { overlay.innerText = "error:" + JSON.stringify(v); overlay.style.backgroundColor = "red"; });
    //     \\  });
    //     \\  document.body.appendChild(overlay);
    //     \\});
    // );

    app.view.navigate(app.provider.getUri("/login.htm") orelse unreachable);
    app.view.run();
}

fn performLogin(app: *App, user_name: []const u8, password: []const u8) !bool {
    if (!std.mem.eql(u8, user_name, "ziggy"))
        return false;
    if (!std.mem.eql(u8, password, "love"))
        return false;

    app.view.navigate(app.provider.getUri("/app.htm") orelse unreachable);

    return true;
}

const std = @import("std");
const wv = @import("positron");

const App = struct {
    arena: std.heap.ArenaAllocator,
    provider: *wv.Provider,
    view: *wv.View,

    user_name: ?[]const u8,

    pub fn getWebView(app: *App) *wv.View {
        return app.view;
    }
};

pub fn main() !void {
    var app = App{
        .arena = std.heap.ArenaAllocator.init(std.heap.c_allocator),
        .provider = undefined,
        .view = undefined,

        .user_name = null,
    };

    app.provider = try wv.Provider.create(std.heap.c_allocator);
    defer app.provider.destroy();

    std.log.info("base uri: {s}", .{app.provider.base_url});

    try app.provider.addContent("/login.htm", "text/html", @embedFile("login.htm"));
    try app.provider.addContent("/app.htm", "text/html", @embedFile("app.htm"));
    try app.provider.addContent("/design.css", "text/css", @embedFile("design.css"));

    const thread = try std.Thread.spawn(.{}, wv.Provider.run, .{app.provider});
    thread.detach();

    app.view = try wv.View.create((std.builtin.mode == .Debug), null);
    defer app.view.destroy();

    app.view.setTitle("Zig Chat");
    app.view.setSize(400, 550, .fixed);

    app.view.bind("performLogin", performLogin, &app);
    app.view.bind("sendMessage", sendMessage, &app);

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

    app.user_name = try app.arena.allocator.dupe(u8, user_name);

    app.view.navigate(app.provider.getUri("/app.htm") orelse unreachable);

    return true;
}

const Message = struct {
    sender: []const u8,
    timestamp: []const u8,
    content: []const u8,
};

fn sendMessage(app: *App, message_text: []const u8) !void {
    std.debug.assert(app.user_name != null);

    var dynamic_buffer = std.ArrayList(u8).init(std.heap.c_allocator);
    defer dynamic_buffer.deinit();

    const writer = dynamic_buffer.writer();

    const message = Message{
        .sender = app.user_name.?,
        .timestamp = "2021-08-02 19:46:30",
        .content = message_text,
    };

    try writer.writeAll("appendMessage(");
    try std.json.stringify(message, .{}, writer);
    try writer.writeAll(");");

    try dynamic_buffer.append(0); // nul terminator

    app.view.eval(dynamic_buffer.items[0 .. dynamic_buffer.items.len - 1 :0]);
}

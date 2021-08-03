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

    const provide_thread = try std.Thread.spawn(.{}, wv.Provider.run, .{app.provider});
    provide_thread.detach();

    std.log.info("provider ready.", .{});

    app.view = try wv.View.create((std.builtin.mode == .Debug), null);
    defer app.view.destroy();

    app.view.setTitle("Zig Chat");
    app.view.setSize(400, 550, .fixed);

    app.view.bind("performLogin", performLogin, &app);
    app.view.bind("sendMessage", sendMessage, &app);

    app.view.navigate(app.provider.getUri("/login.htm") orelse unreachable);

    std.log.info("webview ready.", .{});

    // must be started here, as we may have a race condition otherwise
    const fake_thread = try std.Thread.spawn(.{}, sendRandomMessagesInBackground, .{&app});
    fake_thread.detach();

    std.log.info("start.", .{});

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
    timestamp: i64,
    content: []const u8,
};

fn sendMessage(app: *App, message_text: []const u8) !void {
    std.debug.assert(app.user_name != null);

    const message = Message{
        .sender = app.user_name.?,
        .timestamp = std.time.milliTimestamp(),
        .content = message_text,
    };

    try appendMessage(app, message);
}

fn appendMessage(app: *App, message: Message) !void {
    var dynamic_buffer = std.ArrayList(u8).init(std.heap.c_allocator);
    defer dynamic_buffer.deinit();

    const writer = dynamic_buffer.writer();

    try writer.writeAll("appendMessage(");
    try std.json.stringify(message, .{}, writer);
    try writer.writeAll(");");

    try dynamic_buffer.append(0); // nul terminator

    app.view.eval(dynamic_buffer.items[0 .. dynamic_buffer.items.len - 1 :0]);
}

fn sendRandomMessagesInBackground(app: *App) !void {
    var random = std.rand.DefaultPrng.init(@ptrToInt(&app));
    const rng = &random.random;
    while (true) {
        const time_seconds = 1.5 + 5.5 * rng.float(f32);

        const ns = @floatToInt(u64, std.time.ns_per_s * time_seconds);

        std.time.sleep(ns);

        try appendMessage(app, Message{
            .sender = senders[rng.intRangeLessThan(usize, 0, senders.len)],
            .timestamp = std.time.milliTimestamp(),
            .content = messages[rng.intRangeLessThan(usize, 0, messages.len)],
        });
    }
}

const senders = [_][]const u8{
    "Your mom",
    "xq",
    "mattnite",
    "Sobeston",
    "Aurame",
    "fengb",
    "Luuk",
    "MasterQ32",
    "Tater",
};

const messages = [_][]const u8{
    "hi",
    "what's up?",
    "I love zig!",
    "How do i exit vim?",
    "I finally finished my project",
    "I'm 90% through the code base!",
    "Where is the documentation for the Zig standard library?",
    "Why does Zig force me to use spaces instead of tabs?",
    "Why does zig fmt have no configuration options?",
    "Why is switching on []u8 (strings) not supported?",
    "vim is better than emacs!",
    "emacs is better than vim!",
    "btw, i use Arch Linux!",
    "… joined the channel!",
    "Как установить компилятор?",
    "Где я нахожу искусство Игуаны?",
    "私は安いリッピングを売っています。 禅に従ってください！",
    "How do I shot web?",
    "No, no, he got a point!",
    "I finally got my 5G shot. Now i can see the truth!",
    "Who do I contact when i want to donate 50k to the ZSF?",
    "Never Gonna Give You Up is actually nice",
    "All your base are belong to us",
    "Somebody set up us the bomb.",
    "Main screen turn on.",
    "You have no chance to survive make your time.",
    "Move 'ZIG'.",
    "For great justice.",
    "The cake is a lie.",
    "Rewrite it in Zig!",
};

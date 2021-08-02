const std = @import("std");

const apple_pie = @import("apple_pie");

pub const SizeHint = enum(c_int) {
    /// Width and height are default size
    none = 0,
    /// Width and height are minimum bounds
    min = 1,
    /// Width and height are maximum bounds
    max = 2,
    /// Window size can not be changed by a user
    fixed = 3,
};

pub const ReturnValue = union(enum) {
    success: [:0]const u8,
    failure: [:0]const u8,
};

pub const WebView = opaque {
    const Self = @This();

    /// Creates a new webview instance. If `allow_debug` is set - developer tools will
    /// be enabled (if the platform supports them). `parent_window` parameter can be a
    /// pointer to the native window handle. If it's non-null - then child WebView
    /// is embedded into the given parent window. Otherwise a new window is created.
    /// Depending on the platform, a GtkWindow, NSWindow or HWND pointer can be
    /// passed here.
    pub fn create(allow_debug: bool, parent_window: ?*c_void) !*Self {
        return webview_create(@boolToInt(allow_debug), parent_window) orelse return error.WebviewError;
    }

    /// Destroys a webview and closes the native window.
    pub fn destroy(self: *Self) void {
        webview_destroy(self);
    }

    /// Runs the main loop until it's terminated. After this function exits - you
    /// must destroy the webview.
    pub fn run(self: *Self) void {
        webview_run(self);
    }

    /// Stops the main loop. It is safe to call this function from another other
    /// background thread.
    pub fn terminate(self: *Self) void {
        webview_terminate(self);
    }

    /// Posts a function to be executed on the main thread. You normally do not need
    /// to call this function, unless you want to tweak the native window.
    pub fn dispatch() void {
        // extern fn webview_dispatch(w: *WebView, func: ?fn (*WebView, ?*c_void) callconv(.C) void, arg: ?*c_void) void;
    }

    // Returns a native window handle pointer. When using GTK backend the pointer
    // is GtkWindow pointer, when using Cocoa backend the pointer is NSWindow
    // pointer, when using Win32 backend the pointer is HWND pointer.
    pub fn getWindow(self: *Self) *c_void {
        return webview_get_window(self) orelse @panic("missing native window!");
    }

    /// Updates the title of the native window. Must be called from the UI thread.
    pub fn setTitle(self: *Self, title: [:0]const u8) void {
        webview_set_title(self, title.ptr);
    }

    /// Updates native window size. 
    pub fn setSize(self: *Self, width: u16, height: u16, hint: SizeHint) void {
        webview_set_size(self, width, height, @enumToInt(hint));
    }

    /// Navigates webview to the given URL. URL may be a data URI, i.e.
    /// `data:text/text,<html>...</html>`. It is often ok not to url-encode it
    /// properly, webview will re-encode it for you.
    pub fn navigate(self: *Self, url: [:0]const u8) void {
        webview_navigate(self, url.ptr);
    }

    /// Injects JavaScript code at the initialization of the new page. Every time
    /// the webview will open a the new page - this initialization code will be
    /// executed. It is guaranteed that code is executed before window.onload.
    pub fn init(self: *Self, js: [:0]const u8) void {
        webview_init(self, js.ptr);
    }

    /// Evaluates arbitrary JavaScript code. Evaluation happens asynchronously, also
    /// the result of the expression is ignored. Use RPC bindings if you want to
    /// receive notifications about the results of the evaluation.
    pub fn eval(self: *Self, js: [:0]const u8) void {
        webview_eval(self, js.ptr);
    }

    /// Binds a callback so that it will appear under the given name as a
    /// global JavaScript function. Internally it uses webview_init(). Callback
    /// receives a request string and a user-provided argument pointer. Request
    /// string is a JSON array of all the arguments passed to the JavaScript
    /// function.
    pub fn bindRaw(self: *Self, name: [:0]const u8, context: anytype, comptime callback: fn (ctx: @TypeOf(context), seq: [:0]const u8, req: [:0]const u8) void) void {
        const Context = @TypeOf(context);
        const Binder = struct {
            fn c_callback(seq: [*c]const u8, req: [*c]const u8, arg: ?*c_void) callconv(.C) void {
                callback(
                    @ptrCast(Context, arg),
                    std.mem.sliceTo(seq, 0),
                    std.mem.sliceTo(req, 0),
                );
            }
        };

        webview_bind(self, name.ptr, Binder.c_callback, context);
    }

    /// Binds a callback so that it will appear under the given name as a
    /// global JavaScript function. The callback will be called with `context` as the first parameter,
    /// all other parameters must be deserializable to JSON. The return value might be a error union,
    /// in which case the error is returned to the JS promise. Otherwise, a normal result is serialized to
    /// JSON and then sent back to JS.
    pub fn bind(self: *Self, name: [:0]const u8, comptime callback: anytype, context: @typeInfo(@TypeOf(callback)).Fn.args[0].arg_type.?) void {
        const Fn = @TypeOf(callback);
        const function_info: std.builtin.TypeInfo.Fn = @typeInfo(Fn).Fn;

        if (function_info.args.len < 1)
            @compileError("Function must take at least the context argument!");

        const ReturnType = function_info.return_type orelse @compileError("Function must be non-generic!");
        const return_info: std.builtin.TypeInfo = @typeInfo(ReturnType);

        const Context = @TypeOf(context);

        const Binder = struct {
            fn getWebView(ctx: Context) *WebView {
                if (Context == *WebView)
                    return ctx;
                return ctx.getWebView();
            }

            fn expectArrayStart(stream: *std.json.TokenStream) !void {
                const tok = (try stream.next()) orelse return error.InvalidJson;
                if (tok != .ArrayBegin)
                    return error.InvalidJson;
            }

            fn expectArrayEnd(stream: *std.json.TokenStream) !void {
                const tok = (try stream.next()) orelse return error.InvalidJson;
                if (tok != .ArrayEnd)
                    return error.InvalidJson;
            }

            fn errorResponse(view: *WebView, seq: [:0]const u8, err: anyerror) void {
                var buffer: [64]u8 = undefined;
                const err_str = std.fmt.bufPrint(&buffer, "\"{s}\"\x00", .{@errorName(err)}) catch @panic("error name too long!");

                view.@"return"(seq, .{ .failure = err_str[0 .. err_str.len - 1 :0] });
            }

            fn successResponse(view: *WebView, seq: [:0]const u8, value: anytype) void {
                var buf = std.ArrayList(u8).init(std.heap.c_allocator);
                defer buf.deinit();

                std.json.stringify(value, .{}, buf.writer()) catch |err| {
                    return errorResponse(view, seq, err);
                };

                buf.append(0) catch |err| {
                    return errorResponse(view, seq, err);
                };

                const str = buf.items;

                view.@"return"(seq, .{ .success = str[0 .. str.len - 1 :0] });
            }

            fn c_callback(seq0: [*c]const u8, req0: [*c]const u8, arg: ?*c_void) callconv(.C) void {
                const cb_context = @ptrCast(Context, arg);

                const view = getWebView(cb_context);

                const seq = std.mem.sliceTo(seq0, 0);
                const req = std.mem.sliceTo(req0, 0);

                // std.log.info("invocation: {*} seq={s} req={s}", .{
                //     view, seq, req,
                // });

                const ArgType = std.meta.ArgsTuple(Fn);

                var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
                defer arena.deinit();

                var parsed_args: ArgType = undefined;
                parsed_args[0] = cb_context;

                var json_parser = std.json.TokenStream.init(req);
                {
                    expectArrayStart(&json_parser) catch |err| {
                        std.log.err("parser start: {}", .{err});
                        return errorResponse(view, seq, err);
                    };

                    comptime var i = 1;
                    inline while (i < function_info.args.len) : (i += 1) {
                        const Type = @TypeOf(parsed_args[i]);
                        parsed_args[i] = std.json.parse(Type, &json_parser, .{
                            .allocator = &arena.allocator,
                            .duplicate_field_behavior = .UseFirst,
                            .ignore_unknown_fields = false,
                            .allow_trailing_data = true,
                        }) catch |err| {
                            if (@errorReturnTrace()) |trace|
                                std.debug.dumpStackTrace(trace.*);
                            std.log.err("parsing argument {d}: {}", .{ i, err });
                            return errorResponse(view, seq, err);
                        };
                    }

                    expectArrayEnd(&json_parser) catch |err| {
                        std.log.err("parser end: {}", .{err});
                        return errorResponse(view, seq, err);
                    };
                }

                const result = @call(.{}, callback, parsed_args);

                // std.debug.print("result: {}\n", .{result});

                if (return_info == .ErrorUnion) {
                    if (result) |value| {
                        return successResponse(view, seq, value);
                    } else |err| {
                        return errorResponse(view, seq, err);
                    }
                } else {
                    successResponse(view, seq, result);
                }
            }
        };

        webview_bind(self, name.ptr, Binder.c_callback, context);
    }

    /// Allows to return a value from the native binding. Original request pointer
    /// must be provided to help internal RPC engine match requests with responses.
    /// If status is zero - result is expected to be a valid JSON result value.
    /// If status is not zero - result is an error JSON object.
    pub fn @"return"(self: *Self, seq: [:0]const u8, result: ReturnValue) void {
        switch (result) {
            .success => |res_text| webview_return(self, seq.ptr, 0, res_text.ptr),
            .failure => |res_text| webview_return(self, seq.ptr, 1, res_text.ptr),
        }
    }
};

test {
    _ = WebView.create;
    _ = WebView.destroy;
    _ = WebView.run;
    _ = WebView.terminate;
    _ = WebView.dispatch;
    _ = WebView.getWindow;
    _ = WebView.setTitle;
    _ = WebView.setSize;
    _ = WebView.navigate;
    _ = WebView.init;
    _ = WebView.eval;
    _ = WebView.bind;
    _ = WebView.bindRaw;
    _ = WebView.@"return";
}

extern fn webview_create(debug: c_int, window: ?*c_void) ?*WebView;
extern fn webview_destroy(w: *WebView) void;
extern fn webview_run(w: *WebView) void;
extern fn webview_terminate(w: *WebView) void;
extern fn webview_dispatch(w: *WebView, func: ?fn (*WebView, ?*c_void) callconv(.C) void, arg: ?*c_void) void;
extern fn webview_get_window(w: *WebView) ?*c_void;
extern fn webview_set_title(w: *WebView, title: [*:0]const u8) void;
extern fn webview_set_size(w: *WebView, width: c_int, height: c_int, hints: c_int) void;
extern fn webview_navigate(w: *WebView, url: [*:0]const u8) void;
extern fn webview_init(w: *WebView, js: [*:0]const u8) void;
extern fn webview_eval(w: *WebView, js: [*:0]const u8) void;
extern fn webview_bind(w: *WebView, name: [*:0]const u8, func: ?fn ([*c]const u8, [*c]const u8, ?*c_void) callconv(.C) void, arg: ?*c_void) void;
extern fn webview_return(w: *WebView, seq: [*:0]const u8, status: c_int, result: [*c]const u8) void;

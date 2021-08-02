# ⚛ Positron

A Zig binding to the [webview](https://github.com/webview/webview) library. Make Zig applications with a nice HTML5 frontend a reality!

## Usage

```zig
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
```

## Contributing
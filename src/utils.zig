const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("emscripten/html5.h");
});

// var log_buf: [2048]u8 = undefined;
pub fn log(comptime format_str: []const u8, attr: anytype) void {
    // if (builtin.os.tag == .emscripten) {
    //     const msg = std.fmt.bufPrint(&log_buf, format_str, attr) catch @panic("Failed calling std.fmt.bufPrint");
    //     c.emscripten_console_log(msg.ptr);
    //     return;
    // }
    std.debug.print(format_str, attr);
}

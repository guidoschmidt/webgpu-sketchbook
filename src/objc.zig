const std = @import("std");

pub extern fn objc_msgSend() void;
pub extern fn sel_getUid(name: [*:0]const u8) ?*anyopaque;
pub extern fn objc_getClass(name: [*:0]const u8) ?*anyopaque;

fn msgSend(obj: anytype, selector_name: [:0]const u8, args: anytype, comptime T: type) T {
    const args_meta = @typeInfo(@TypeOf(args)).@"struct".fields;

    const FunctionType = switch (args_meta.len) {
        0 => *const fn (@TypeOf(obj), ?*anyopaque) callconv(.c) T,
        1 => *const fn (@TypeOf(obj), ?*anyopaque, args_meta[0].type) callconv(.c) T,
        else => @panic("Not implemented"),
    };

    const func = @as(FunctionType, @ptrCast(&objc_msgSend));
    const selector = sel_getUid(selector_name.ptr);

    return @call(.never_inline, func, .{ obj, selector } ++ args);
}

pub fn getMetalLayer(window: *anyopaque) *anyopaque {
    const content_view = msgSend(window, "contentView", .{}, *anyopaque);
    std.debug.print("\nContent View: {any}", .{content_view});

    msgSend(content_view, "setWantsLayer:", .{true}, void);

    const layer_class = objc_getClass("CAMetalLayer");
    const layer = msgSend(layer_class, "layer", .{}, ?*anyopaque);
    if (layer_class == null) @panic("Failed to retrieve metal layer");
    if (layer == null) @panic("Failed to retrieve metal layer");
    std.debug.print("\nLayer Class: {any}", .{layer_class});
    std.debug.print("\nLayer: {any}", .{layer});

    msgSend(content_view, "setLayer:", .{layer.?}, void);

    const scale_factor = msgSend(window, "backingScaleFactor", .{}, f64);
    std.debug.print("\nLayer scale factor: {d}", .{scale_factor});

    msgSend(layer.?, "setContentsScale:", .{scale_factor}, void);

    return layer.?;
}

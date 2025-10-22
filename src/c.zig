const builtin = @import("builtin");

pub const wgpu = @cImport({
    if (builtin.os.tag == .emscripten) {
        @cInclude("webgpu/webgpu.h");
    } else {
        @cInclude("webgpu.h");
    }
});
pub const emsc = @cImport({
    if (builtin.os.tag == .emscripten) {
        @cInclude("emscripten.h");
        @cInclude("emscripten/html5.h");
    }
});

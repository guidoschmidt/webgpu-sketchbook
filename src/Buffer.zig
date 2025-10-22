const wgpu = @import("c.zig").wgpu;
const builtin = @import("builtin");
const emsc = @import("c.zig").wgpu;

pub fn WGPUBufferUsage(comptime usage: u64) type {
    if (builtin.os.tag == .emscripten) {
        return struct {
            pub fn get() u32 {
                return wgpu.WGPUBufferUsage_CopyDst | usage;
            }
        };
    } else {
        return struct {
            pub fn get() u64 {
                return wgpu.WGPUBufferUsage_CopyDst | usage;
            }
        };
    }
}

pub fn WGPUStringView(str: []const u8) type {
    // if (builtin.os.tag == .emscripten) {
    //     return struct {
    //         pub fn get() [*c]const u8 {
    //             return @ptrCast(str);
    //         }
    //     };
    // } else {
    return struct {
        pub fn get() wgpu.WGPUStringView {
            return .{
                .data = @ptrCast(str),
                .length = wgpu.WGPU_STRLEN,
            };
        }
    };
    // }
}

pub const BufferUsage = enum(u64) {
    Storage = wgpu.WGPUBufferUsage_Storage,
    CopySrc = wgpu.WGPUBufferUsage_CopySrc,
    CopyDst = wgpu.WGPUBufferUsage_CopyDst,
    Uniform = wgpu.WGPUBufferUsage_Uniform,
    MapRead = wgpu.WGPUBufferUsage_MapRead,
    Vertex = wgpu.WGPUBufferUsage_Vertex,
    Index = wgpu.WGPUBufferUsage_Index,
};

fn createBuffer(
    comptime U: type,
    comptime label: []const u8,
    count: usize,
    device: wgpu.WGPUDevice,
    comptime usage: wgpu.WGPUBufferUsage,
) wgpu.WGPUBuffer {
    return wgpu.wgpuDeviceCreateBuffer(
        device,
        &wgpu.WGPUBufferDescriptor{
            .label = WGPUStringView(label).get(),
            .usage = WGPUBufferUsage(usage).get(),
            .size = @sizeOf(U) * count,
        },
    );
}

pub fn Buffer(
    comptime T: type,
    comptime count: usize,
    comptime usage: []const BufferUsage,
) type {
    return struct {
        const Self = @This();

        data: ?T,
        size: usize,
        usage: []const BufferUsage,
        buffer: wgpu.WGPUBuffer = undefined,
        layout: wgpu.WGPUBindGroupLayout = undefined,
        bind_group: ?wgpu.WGPUBindGroup = undefined,

        pub fn init(
            device: wgpu.WGPUDevice,
            comptime label: []const u8,
            comptime data: ?*T,
        ) Buffer(T, count, usage) {
            comptime var usage_mask: u64 = 0;
            inline for (usage) |u| {
                usage_mask = usage_mask | @intFromEnum(u);
            }
            return .{
                .data = if (data != null) data.?.* else null,
                .size = @sizeOf(@TypeOf(data)),
                .usage = usage,
                .buffer = createBuffer(
                    T,
                    label,
                    count,
                    device,
                    usage_mask,
                ),
            };
        }

        pub fn upload(self: Self, queue: wgpu.WGPUQueue) void {
            wgpu.wgpuQueueWriteBuffer(
                queue,
                self.buffer,
                0,
                &self.data.?,
                self.size,
            );
        }
    };
}

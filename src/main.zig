const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const objc = @import("objc.zig");
const wgpu = @import("c.zig").wgpu;
const emsc = @import("c.zig").emsc;
const Buffer = @import("Buffer.zig").Buffer;

const Uniforms = packed struct {
    time: f32,
    colorshift: f32,
    rest: @Vector(2, f32) = @splat(0),
};

var uniforms: Uniforms = .{
    .time = 0,
    .colorshift = 0,
};

const RequestAdapterUserData = struct {
    done: bool = false,
    adapter: wgpu.WGPUAdapter = undefined,
};

const RequestDeviceUserData = struct {
    done: bool = false,
    device: wgpu.WGPUDevice = undefined,
};

const Vertex = struct {
    position: [3]f32 = undefined,
    color: [3]f32 = undefined,
    uv: [2]f32 = undefined,
};

const t: f32 = 0.9;
var vertices = [_]Vertex{
    .{
        .position = .{ -t, -t, 1.0 },
        .color = .{ 0, 1, 0 },
        .uv = .{ 0, 0 },
    },
    .{
        .position = .{ t, -t, 0.0 },
        .color = .{ 1, 1, 1 },
        .uv = .{ 1, 0 },
    },
    .{
        .position = .{ t, t, 0.0 },
        .color = .{ 1, 0, 1 },
        .uv = .{ 1, 1 },
    },
    .{
        .position = .{ -t, t, 1.0 },
        .color = .{ 1, 1, 0 },
        .uv = .{ 0, 1 },
    },
};
var vertex_data: []Vertex = &vertices;

var indices = [_]u16{
    0, 1, 2,
    0, 2, 3,
};
var index_data: []u16 = &indices;

// Global CTX state
var adapter: wgpu.WGPUAdapter = undefined;
var device: wgpu.WGPUDevice = undefined;
var surface: wgpu.WGPUSurface = undefined;
var capabilities: wgpu.WGPUSurfaceCapabilities = undefined;
var config: wgpu.WGPUSurfaceConfiguration = undefined;
var render_pipeline: wgpu.WGPURenderPipeline = undefined;
var bind_group: wgpu.WGPUBindGroup = undefined;
var vertex_buffer: wgpu.WGPUBuffer = undefined;
var index_buffer: wgpu.WGPUBuffer = undefined;
var uniform_buffer: wgpu.WGPUBuffer = undefined;
var queue: wgpu.WGPUQueue = undefined;

fn WGPUBufferUsage(comptime usage: u64) type {
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

pub fn createBuffer(
    comptime T: type,
    comptime label: []const u8,
    count: usize,
    comptime usage: wgpu.WGPUBufferUsage,
) wgpu.WGPUBuffer {
    const buffer = wgpu.wgpuDeviceCreateBuffer(
        device,
        &wgpu.WGPUBufferDescriptor{
            .label = wgpu.WGPUStringView{
                .data = label.ptr,
                .length = wgpu.WGPU_STRLEN,
            },
            .usage = WGPUBufferUsage(usage).get(),
            .size = @sizeOf(T) * count,
        },
    );
    return buffer;
}

pub fn printAdapterInfo() void {
    var info = wgpu.WGPUAdapterInfo{};
    const status = wgpu.wgpuAdapterGetInfo(adapter, &info);
    if (status == wgpu.WGPUStatus_Success) {
        var description: []const u8 = undefined;
        description.ptr = info.description.data;
        description.len = info.description.length;
        std.debug.print("Description: {s}\n", .{description});
        var vendor: []const u8 = undefined;
        vendor.ptr = info.vendor.data;
        vendor.len = info.vendor.length;
        std.debug.print("Vendor: {s}\n", .{vendor});
        var device_info: []const u8 = undefined;
        device_info.ptr = info.device.data;
        device_info.len = info.device.length;
        std.debug.print("Device: {s}\n", .{device_info});
        std.debug.print("Backend: {d}\n", .{info.backendType});
        std.debug.print("Adapter: {d}\n", .{info.adapterType});
        std.debug.print("Vendor ID: {d}\n", .{info.vendorID});
        std.debug.print("Device ID: {d}\n", .{info.deviceID});
    }
}

pub fn createVertexAttributes(
    comptime T: type,
) [@typeInfo(T).@"struct".fields.len]wgpu.WGPUVertexAttribute {
    const type_info = @typeInfo(T);
    const fields = type_info.@"struct".fields;
    var array: [fields.len]wgpu.WGPUVertexAttribute = undefined;
    comptime var i: usize = 0;
    inline while (i < fields.len) : (i += 1) {
        const format = switch (fields[i].type) {
            f32 => wgpu.WGPUVertexFormat_Float32,
            @Vector(2, f32), [2]f32 => wgpu.WGPUVertexFormat_Float32x2,
            @Vector(3, f32), [3]f32 => wgpu.WGPUVertexFormat_Float32x3,
            @Vector(4, f32), [4]f32 => wgpu.WGPUVertexFormat_Float32x4,
            else => wgpu.WGPUVertexFormat_Float32,
        };
        const entry = wgpu.WGPUVertexAttribute{
            .format = format,
            .shaderLocation = i,
            .offset = @offsetOf(T, fields[i].name),
        };
        array[i] = entry;
    }
    return array;
}

fn draw() callconv(.c) void {
    uniforms.time += 0.01;
    uniforms.colorshift += 0.01;

    const uniforms_ptr: *align(16) Uniforms = @alignCast(&uniforms);
    wgpu.wgpuQueueWriteBuffer(
        queue,
        uniform_buffer,
        0,
        uniforms_ptr,
        @sizeOf(Uniforms),
    );

    var surface_texture: wgpu.WGPUSurfaceTexture = undefined;
    wgpu.wgpuSurfaceGetCurrentTexture(surface, &surface_texture);
    const frame = wgpu.wgpuTextureCreateView(surface_texture.texture, null);
    std.debug.assert(frame != null);

    const command_encoder = wgpu.wgpuDeviceCreateCommandEncoder(
        device,
        &wgpu.WGPUCommandEncoderDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Command Encoder",
                .length = wgpu.WGPU_STRLEN,
            },
        },
    );
    std.debug.assert(command_encoder != null);

    const render_pass_encoder = wgpu.wgpuCommandEncoderBeginRenderPass(
        command_encoder,
        &wgpu.WGPURenderPassDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Render Pass Encoder",
                .length = wgpu.WGPU_STRLEN,
            },
            .colorAttachmentCount = 1,
            .colorAttachments = &[_]wgpu.WGPURenderPassColorAttachment{
                wgpu.WGPURenderPassColorAttachment{
                    .view = frame,
                    .loadOp = wgpu.WGPULoadOp_Clear,
                    .storeOp = wgpu.WGPUStoreOp_Store,
                    .depthSlice = wgpu.WGPU_DEPTH_SLICE_UNDEFINED,
                    .clearValue = wgpu.WGPUColor{
                        .r = 0,
                        .g = 0,
                        .b = 0,
                        .a = 1,
                    },
                },
            },
        },
    );
    std.debug.assert(render_pass_encoder != null);

    wgpu.wgpuRenderPassEncoderSetPipeline(render_pass_encoder, render_pipeline);
    wgpu.wgpuRenderPassEncoderSetBindGroup(render_pass_encoder, 0, bind_group, 0, 0);

    wgpu.wgpuRenderPassEncoderSetVertexBuffer(
        render_pass_encoder,
        0,
        vertex_buffer,
        0,
        wgpu.WGPU_WHOLE_SIZE,
    );
    wgpu.wgpuRenderPassEncoderSetIndexBuffer(
        render_pass_encoder,
        index_buffer,
        wgpu.WGPUIndexFormat_Uint16,
        0,
        wgpu.WGPU_WHOLE_SIZE,
    );
    wgpu.wgpuRenderPassEncoderDrawIndexed(render_pass_encoder, 6, 1, 0, 0, 0);

    wgpu.wgpuRenderPassEncoderEnd(render_pass_encoder);
    wgpu.wgpuRenderPassEncoderRelease(render_pass_encoder);

    const command_buffer = wgpu.wgpuCommandEncoderFinish(
        command_encoder,
        &wgpu.WGPUCommandBufferDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Command Buffer",
                .length = wgpu.WGPU_STRLEN,
            },
        },
    );
    std.debug.assert(command_buffer != null);

    wgpu.wgpuQueueSubmit(queue, 1, &[_]wgpu.WGPUCommandBuffer{
        command_buffer,
    });

    if (builtin.os.tag != .emscripten) {
        _ = wgpu.wgpuSurfacePresent(surface);
    }

    wgpu.wgpuCommandBufferRelease(command_buffer);
    wgpu.wgpuCommandEncoderRelease(command_encoder);
    wgpu.wgpuTextureViewRelease(frame);
}

fn handleRequestAdapter(
    status: wgpu.WGPURequestAdapterStatus,
    resolved_adapter: wgpu.WGPUAdapter,
    message: wgpu.WGPUStringView,
    user_data1: ?*anyopaque,
    user_data2: ?*anyopaque,
) callconv(.c) void {
    _ = user_data2;
    _ = message;
    if (status == wgpu.WGPURequestAdapterStatus_Success) {
        std.debug.print("[Request Adapter] Status: {d}\n", .{status});
        const user_data: ?*RequestAdapterUserData = @ptrCast(@alignCast(user_data1));
        user_data.?.done = true;
        user_data.?.adapter = resolved_adapter;
    } else {
        std.debug.print("[ERROR/Request Adapter] Status: {d}\n", .{status});
    }
}

fn handleRequestDevice(
    status: wgpu.WGPURequestDeviceStatus,
    resolved_device: wgpu.WGPUDevice,
    message: wgpu.WGPUStringView,
    user_data1: ?*anyopaque,
    user_data2: ?*anyopaque,
) callconv(.c) void {
    _ = user_data2;
    _ = message;
    if (status == wgpu.WGPURequestDeviceStatus_Success) {
        std.debug.print("[Request Device] Status: {d}\n", .{status});
        const user_data: ?*RequestDeviceUserData = @ptrCast(@alignCast(user_data1));
        user_data.?.done = true;
        user_data.?.device = resolved_device;
        return;
    } else {
        std.debug.print("[ERROR/Request Device] Status: {d}\n", .{status});
    }
}

fn setup() !void {
    try glfw.init();
    defer glfw.terminate();

    const width = 720;
    const height = 720;
    glfw.windowHint(.CLIENT_API, .NO_API);
    const window = glfw.createWindow(width, height, "[wgpu-native + glfw]", null);
    // _ = window;

    const instance = wgpu.wgpuCreateInstance(null);
    std.debug.assert(instance != null);
    std.debug.print("Instance: {*}\n", .{instance});

    if (builtin.os.tag == .emscripten) {
        device = wgpu.emscripten_webgpu_get_device();
        std.debug.print("Device: {*}\n", .{device});
    } else {
        if (builtin.os.tag == .macos) {
            const metal_layer = objc.getMetalLayer(glfw.getCocoaWindow(window).?);
            std.debug.print("\nMetal Layer: {any}", .{metal_layer});

            var wgpu_surface_source_metal_layer = wgpu.WGPUSurfaceSourceMetalLayer{
                .chain = wgpu.WGPUChainedStruct{
                    .sType = wgpu.WGPUSType_SurfaceSourceMetalLayer,
                },
                .layer = metal_layer,
            };

            surface = wgpu.wgpuInstanceCreateSurface(
                instance,
                &wgpu.WGPUSurfaceDescriptor{
                    .label = wgpu.WGPUStringView{
                        .data = "Surface/macOS",
                        .length = wgpu.WGPU_STRLEN,
                    },
                    .nextInChain = @ptrCast(&wgpu_surface_source_metal_layer),
                },
            );
            std.debug.print("Surface: {any}\n", .{surface});
            std.debug.assert(surface != null);
        }

        var request_adatper_userdata = RequestAdapterUserData{};
        _ = wgpu.wgpuInstanceRequestAdapter(
            instance,
            &wgpu.WGPURequestAdapterOptions{
                .compatibleSurface = surface,
            },
            wgpu.WGPURequestAdapterCallbackInfo{
                .callback = handleRequestAdapter,
                .userdata1 = &request_adatper_userdata,
            },
        );
        adapter = request_adatper_userdata.adapter;
        std.debug.print("Adapter: {*}\n", .{adapter});
        std.debug.assert(adapter != null);
        printAdapterInfo();

        var request_device_userdata = RequestDeviceUserData{};
        _ = wgpu.wgpuAdapterRequestDevice(
            adapter,
            null,
            // &wgpu.WGPUDeviceDescriptor{
            //     .label = wgpu.WGPUStringView{
            //         .data = "Device",
            //         .length = wgpu.WGPU_STRLEN,
            //     },
            //     .nextInChain = null,
            //     .deviceLostCallbackInfo = .{},
            //     .requiredFeatureCount = 0,
            //     .requiredLimits = null,
            // },
            wgpu.WGPURequestDeviceCallbackInfo{
                .callback = handleRequestDevice,
                .userdata1 = &request_device_userdata,
            },
        );
        device = request_device_userdata.device;
        std.debug.print("Device: {*}\n", .{device});
        std.debug.assert(device != null);
    }

    queue = wgpu.wgpuDeviceGetQueue(device);
    std.debug.print("Queue: {*}\n", .{queue});
    std.debug.assert(queue != null);

    if (builtin.os.tag == .emscripten) {
        _ = emsc.emscripten_set_canvas_element_size(
            "canvas",
            @intCast(width),
            @intCast(height),
        );

        const canvas_selector = wgpu.WGPUEmscriptenSurfaceSourceCanvasHTMLSelector{
            .chain = wgpu.WGPUChainedStruct{
                .sType = wgpu.WGPUSType_EmscriptenSurfaceSourceCanvasHTMLSelector,
            },
            .selector = wgpu.WGPUStringView{
                .data = "canvas",
                .length = wgpu.WGPU_STRLEN,
            },
        };
        const surface_descriptor = wgpu.WGPUSurfaceDescriptor{
            .nextInChain = @ptrCast(@constCast(&canvas_selector)),
        };
        surface = wgpu.wgpuInstanceCreateSurface(instance, &surface_descriptor);
        std.debug.print("Surface: {*}\n", .{surface});

        const surface_config = wgpu.WGPUSurfaceConfiguration{
            .device = device,
            .usage = wgpu.WGPUTextureUsage_RenderAttachment,
            .format = wgpu.WGPUTextureFormat_BGRA8Unorm,
            .presentMode = wgpu.WGPUPresentMode_Fifo,
            .width = width,
            .height = height,
            .alphaMode = wgpu.WGPUCompositeAlphaMode_Auto,
        };
        wgpu.wgpuSurfaceConfigure(surface, &surface_config);
    } else {
        _ = wgpu.wgpuSurfaceGetCapabilities(surface, adapter, &capabilities);

        const surface_config = wgpu.WGPUSurfaceConfiguration{
            .device = device,
            .usage = wgpu.WGPUTextureUsage_RenderAttachment,
            .format = capabilities.formats[0],
            .presentMode = wgpu.WGPUPresentMode_Fifo,
            .alphaMode = capabilities.alphaModes[0],
            .width = width,
            .height = height,
        };
        wgpu.wgpuSurfaceConfigure(surface, &surface_config);
    }

    // SHADER
    const shader_code = @embedFile("shader.basic");
    const shader_module = wgpu.wgpuDeviceCreateShaderModule(
        device,
        &wgpu.WGPUShaderModuleDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Shader Module",
                .length = wgpu.WGPU_STRLEN,
            },
            .nextInChain = @ptrCast(@constCast(
                &wgpu.WGPUShaderSourceWGSL{
                    .chain = wgpu.WGPUChainedStruct{
                        .sType = wgpu.WGPUSType_ShaderSourceWGSL,
                    },
                    .code = .{
                        .data = shader_code.ptr,
                        .length = wgpu.WGPU_STRLEN,
                    },
                },
            )),
        },
    );
    std.debug.print("Shader: {*}\n", .{shader_module});
    std.debug.assert(shader_module != null);

    uniform_buffer = createBuffer(
        Uniforms,
        "Uniform Buffer",
        1,
        wgpu.WGPUBufferUsage_Uniform,
    );
    std.debug.assert(uniform_buffer != null);
    std.debug.print("Uniform Buffer: {any}\n", .{uniform_buffer});

    const vertex_attributes_auto = createVertexAttributes(Vertex);
    std.debug.print("\n\nVertex Attributes: {any}\n", .{vertex_attributes_auto});

    const vertex_buffer_layout = wgpu.WGPUVertexBufferLayout{
        .arrayStride = @sizeOf(Vertex),
        .stepMode = wgpu.WGPUVertexStepMode_Vertex,
        .attributeCount = vertex_attributes_auto.len,
        .attributes = &vertex_attributes_auto,
    };
    std.debug.print("\n\nVertex Buffer Layout: {any}\n", .{vertex_buffer_layout});

    const bind_group_layout_entries = &[_]wgpu.WGPUBindGroupLayoutEntry{
        wgpu.WGPUBindGroupLayoutEntry{
            .binding = 0,
            .visibility = wgpu.WGPUShaderStage_Vertex | wgpu.WGPUShaderStage_Fragment,
            .buffer = wgpu.WGPUBufferBindingLayout{
                .type = wgpu.WGPUBufferBindingType_Uniform,
                .hasDynamicOffset = @intFromBool(false),
            },
        },
    };
    const bind_group_layout = wgpu.wgpuDeviceCreateBindGroupLayout(
        device,
        &wgpu.WGPUBindGroupLayoutDescriptor{
            .entryCount = bind_group_layout_entries.len,
            .entries = bind_group_layout_entries,
        },
    );

    const bind_group_entries = [_]wgpu.WGPUBindGroupEntry{
        wgpu.WGPUBindGroupEntry{
            .binding = 0,
            .buffer = uniform_buffer,
            .offset = 0,
            .size = @sizeOf(Uniforms),
        },
    };

    bind_group = wgpu.wgpuDeviceCreateBindGroup(
        device,
        &wgpu.WGPUBindGroupDescriptor{
            .layout = bind_group_layout,
            .entryCount = bind_group_entries.len,
            .entries = &bind_group_entries,
        },
    );
    std.debug.assert(bind_group != null);
    std.debug.print("Bind Group: {any}\n", .{bind_group});

    // PIPELINE
    const pipeline_layout = wgpu.wgpuDeviceCreatePipelineLayout(
        device,
        &wgpu.WGPUPipelineLayoutDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Pipeline Layout",
                .length = wgpu.WGPU_STRLEN,
            },
            .bindGroupLayoutCount = 1,
            .bindGroupLayouts = &bind_group_layout,
        },
    );
    std.debug.assert(pipeline_layout != null);

    render_pipeline = wgpu.wgpuDeviceCreateRenderPipeline(
        device,
        &wgpu.WGPURenderPipelineDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Render Pipeline",
                .length = wgpu.WGPU_STRLEN,
            },
            .layout = pipeline_layout,
            .vertex = wgpu.WGPUVertexState{
                .module = shader_module,
                .entryPoint = wgpu.WGPUStringView{
                    .data = "vs_main",
                    .length = wgpu.WGPU_STRLEN,
                },
                .bufferCount = 1,
                .buffers = &[_]wgpu.WGPUVertexBufferLayout{
                    vertex_buffer_layout,
                },
            },
            .fragment = &wgpu.WGPUFragmentState{
                .module = shader_module,
                .entryPoint = wgpu.WGPUStringView{
                    .data = "fs_main",
                    .length = wgpu.WGPU_STRLEN,
                },
                .targetCount = 1,
                .targets = &[_]wgpu.WGPUColorTargetState{
                    wgpu.WGPUColorTargetState{
                        .format = if (builtin.os.tag == .emscripten) wgpu.WGPUTextureFormat_BGRA8Unorm else capabilities.formats[0],
                        .writeMask = wgpu.WGPUColorWriteMask_All,
                    },
                },
            },
            .primitive = wgpu.WGPUPrimitiveState{
                .frontFace = wgpu.WGPUFrontFace_CCW,
                .cullMode = wgpu.WGPUCullMode_None,
                .topology = wgpu.WGPUPrimitiveTopology_TriangleList,
                .stripIndexFormat = wgpu.WGPUIndexFormat_Undefined,
            },
            .multisample = wgpu.WGPUMultisampleState{
                .count = 1,
                .mask = 0xFFFFFFFF,
            },
        },
    );
    std.debug.assert(render_pipeline != null);
    std.debug.print("Render Pipeline: {*}\n", .{render_pipeline});

    // UPLOAD GEOMETRY
    vertex_buffer = createBuffer(
        Vertex,
        "Vertex Buffer",
        vertices.len,
        wgpu.WGPUBufferUsage_Vertex,
    );
    index_buffer = createBuffer(
        u16,
        "Index Buffer",
        indices.len,
        wgpu.WGPUBufferUsage_Index,
    );
    wgpu.wgpuQueueWriteBuffer(
        queue,
        vertex_buffer,
        0,
        vertex_data.ptr,
        @sizeOf(Vertex) * vertex_data.len,
    );
    wgpu.wgpuQueueWriteBuffer(
        queue,
        index_buffer,
        0,
        index_data.ptr,
        @sizeOf(u16) * index_data.len,
    );
    std.debug.print("Vertex + Index Buffer:\n{any}\n{any}\n", .{ vertex_buffer, index_buffer });

    // DRAW
    if (builtin.os.tag == .emscripten) {
        emsc.emscripten_set_main_loop(draw, 0, true);
    } else {
        while (!glfw.shouldClose(window)) {
            if (glfw.getKey(window, .escape) == .press) break;
            glfw.pollEvents();

            draw();
        }
    }

    // DEINIT
    wgpu.wgpuInstanceRelease(instance);
}

pub fn main() !void {
    try setup();
}

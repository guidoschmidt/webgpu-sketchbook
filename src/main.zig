const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const objc = @import("objc.zig");
const log = @import("utils.zig").log;
const wgpu = @import("c.zig").wgpu;
const emsc = @import("c.zig").emsc;
const Buffer = @import("Buffer.zig").Buffer;
const zstbi = @import("zstbi");

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

const MappedBufferUserData = struct {
    done: bool = false,
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
const width = 256;
const height = 256;

var window: *glfw.Window = undefined;
var instance: wgpu.WGPUInstance = undefined;
var adapter: wgpu.WGPUAdapter = undefined;
var device: wgpu.WGPUDevice = undefined;
var surface: wgpu.WGPUSurface = undefined;
var capabilities: wgpu.WGPUSurfaceCapabilities = undefined;
var texture_format: wgpu.WGPUTextureFormat = wgpu.WGPUTextureFormat_BGRA8Unorm;
var config: wgpu.WGPUSurfaceConfiguration = undefined;
var render_pipeline: wgpu.WGPURenderPipeline = undefined;
var bind_group: wgpu.WGPUBindGroup = undefined;
var vertex_buffer: wgpu.WGPUBuffer = undefined;
var index_buffer: wgpu.WGPUBuffer = undefined;
var uniform_buffer: wgpu.WGPUBuffer = undefined;
var pixel_buffer: wgpu.WGPUBuffer = undefined;
var queue: wgpu.WGPUQueue = undefined;

var frame_number: usize = 0;
var record_frame_count: usize = 60;

var target_texture: wgpu.WGPUTexture = undefined;
var target_texture_view: wgpu.WGPUTextureView = undefined;

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

pub fn createTexture() wgpu.WGPUTexture {
    const texture_descriptor = wgpu.WGPUTextureDescriptor{
        .nextInChain = null,
        .label = wgpu.WGPUStringView{
            .data = "RenderTarget",
            .length = wgpu.WGPU_STRLEN,
        },
        .dimension = wgpu.WGPUTextureDimension_2D,
        .size = .{
            .width = width,
            .height = height,
            .depthOrArrayLayers = 1,
        },
        .format = wgpu.WGPUTextureFormat_RGBA8Unorm,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .usage = wgpu.WGPUTextureUsage_TextureBinding | wgpu.WGPUTextureUsage_RenderAttachment | wgpu.WGPUTextureUsage_CopySrc,
        .viewFormatCount = 0,
        .viewFormats = null,
    };
    return wgpu.wgpuDeviceCreateTexture(device, &texture_descriptor);
}

pub fn createTextureView(texture: wgpu.WGPUTexture) wgpu.WGPUTextureView {
    const texture_view_descriptor = wgpu.WGPUTextureViewDescriptor{
        .nextInChain = null,
        .label = wgpu.WGPUStringView{
            .data = "RenderTexutreView",
            .length = wgpu.WGPU_STRLEN,
        },
        .baseArrayLayer = 0,
        .arrayLayerCount = 1,
        .baseMipLevel = 0,
        .mipLevelCount = 1,
        .aspect = wgpu.WGPUTextureAspect_All,
    };
    return wgpu.wgpuTextureCreateView(texture, &texture_view_descriptor);
}

pub fn printAdapterInfo() void {
    var info = wgpu.WGPUAdapterInfo{};
    const status = wgpu.wgpuAdapterGetInfo(adapter, &info);
    if (status == wgpu.WGPUStatus_Success) {
        var description: []const u8 = undefined;
        description.ptr = info.description.data;
        description.len = info.description.length;
        log("Description: {s}\n", .{description});
        var vendor: []const u8 = undefined;
        vendor.ptr = info.vendor.data;
        vendor.len = info.vendor.length;
        log("Vendor: {s}\n", .{vendor});
        var device_info: []const u8 = undefined;
        device_info.ptr = info.device.data;
        device_info.len = info.device.length;
        log("Device: {s}\n", .{device_info});
        log("Backend: {d}\n", .{info.backendType});
        log("Adapter: {d}\n", .{info.adapterType});
        log("Vendor ID: {d}\n", .{info.vendorID});
        log("Device ID: {d}\n", .{info.deviceID});
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
    // Update Uniforms
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

    // Get Texture from sufrace (disable for headless rendering)
    var surface_texture: wgpu.WGPUSurfaceTexture = undefined;
    wgpu.wgpuSurfaceGetCurrentTexture(surface, &surface_texture);
    const frame = wgpu.wgpuTextureCreateView(surface_texture.texture, null);
    std.debug.assert(frame != null);

    // Headless rendering
    // headless: {
    //     const frame = target_texture_view;
    //     break :headless;
    // }

    // Command Encoder
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
            .colorAttachmentCount = 2,
            .colorAttachments = &[_]wgpu.WGPURenderPassColorAttachment{
                wgpu.WGPURenderPassColorAttachment{
                    .view = target_texture_view,
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

    wgpu.wgpuCommandEncoderCopyTextureToBuffer(
        command_encoder,
        &wgpu.WGPUTexelCopyTextureInfo{
            .texture = target_texture,
            .mipLevel = 0,
            .origin = .{},
            .aspect = wgpu.WGPUTextureAspect_All,
        },
        &wgpu.WGPUTexelCopyBufferInfo{
            .layout = wgpu.WGPUTexelCopyBufferLayout{
                .offset = 0,
                .bytesPerRow = @sizeOf(u32) * width,
                .rowsPerImage = height,
            },
            .buffer = pixel_buffer,
        },
        &wgpu.WGPUExtent3D{
            .width = width,
            .height = height,
            .depthOrArrayLayers = 1,
        },
    );

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

    save_texture_to_file: {
        var user_data = MappedBufferUserData{};
        _ = wgpu.wgpuBufferMapAsync(
            pixel_buffer,
            wgpu.WGPUMapMode_Read,
            0,
            width * height * 4,
            wgpu.WGPUBufferMapCallbackInfo{
                .mode = wgpu.WGPUCallbackMode_AllowSpontaneous,
                .callback = handleMappedPixelBuffer,
                .userdata1 = &user_data,
            },
        );
        while (!user_data.done) {
            // log("[Pixel Buffer Map Async] Waiting...\n", .{});
            wgpu.wgpuInstanceProcessEvents(instance);
        }
        break :save_texture_to_file;
    }

    // Only use for non-headless rendering
    if (builtin.os.tag != .emscripten) {
        _ = wgpu.wgpuSurfacePresent(surface);
    }

    wgpu.wgpuCommandBufferRelease(command_buffer);
    wgpu.wgpuCommandEncoderRelease(command_encoder);

    // Only enable for non-headless rendering
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
        log("[Request Adapter] Status: {d}\n", .{status});
        const user_data: ?*RequestAdapterUserData = @ptrCast(@alignCast(user_data1));
        user_data.?.done = true;
        user_data.?.adapter = resolved_adapter;
    } else {
        log("[ERROR/Request Adapter] Status: {d}\n", .{status});
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
        log("[Request Device] Status: {d}\n", .{status});
        const user_data: ?*RequestDeviceUserData = @ptrCast(@alignCast(user_data1));
        user_data.?.done = true;
        user_data.?.device = resolved_device;
        return;
    } else {
        log("[ERROR/Request Device] Status: {d}\n", .{status});
    }
}

fn handleMappedBuffer(
    status: wgpu.WGPUMapAsyncStatus,
    message: wgpu.WGPUStringView,
    user_data1: ?*anyopaque,
    user_data2: ?*anyopaque,
) callconv(.c) void {
    _ = message;
    _ = user_data2;
    log("[Map Buffer Async] Status: {any}\n", .{status});
    if (status > 0) {
        const user_data: ?*MappedBufferUserData = @ptrCast(@alignCast(user_data1));
        user_data.?.done = true;
        return;
    }
    log("[ERROR/Map Buffer Async] Status: {any}\n", .{status});
}

fn handleMappedPixelBuffer(
    status: wgpu.WGPUMapAsyncStatus,
    message: wgpu.WGPUStringView,
    user_data1: ?*anyopaque,
    user_data2: ?*anyopaque,
) callconv(.c) void {
    _ = message;
    _ = user_data2;
    // log("[Map Pixel Buffer Async] Status: {any}\n", .{status});
    if (status == wgpu.WGPUMapAsyncStatus_Success) {
        const user_data: ?*MappedBufferUserData = @ptrCast(@alignCast(user_data1));

        const data = @as([]u8, @ptrCast(@constCast(wgpu.wgpuBufferGetConstMappedRange(
            pixel_buffer,
            0,
            @sizeOf(u8) * width * height * 4,
        ))));
        const img = zstbi.Image{
            .width = @intCast(width),
            .height = @intCast(height),
            .num_components = 4,
            .data = data[0..],
            .bytes_per_row = @intCast(width),
            .bytes_per_component = 1,
            .is_hdr = false,
        };

        var temp_buffer: [256]u8 = undefined;
        const filename = std.fmt.bufPrintZ(
            &temp_buffer,
            "frame_{d:0>4}.png",
            .{frame_number},
        ) catch @panic("Failed to std.fmt.bufPrintZ\n");
        zstbi.Image.writeToFile(img, filename, .png) catch |err| {
            std.log.err("{any}", .{err});
        };

        user_data.?.done = true;
        wgpu.wgpuBufferUnmap(pixel_buffer);
        return;
    }
    log("[ERROR/Map Pixel Buffer Async] Status: {any}\n", .{status});
}

fn setup() !void {
    // const instance_descriptor = wgpu.WGPUInstanceDescriptor{
    //     .requiredFeatureCount = 1,
    //     .requiredFeatures = wgpu.WGPUInstanceFeatureName_TimedWaitAny,
    // };
    instance = wgpu.wgpuCreateInstance(null);
    std.debug.assert(instance != null);
    log("Instance: {*}\n", .{instance});

    if (builtin.os.tag == .emscripten) {
        device = wgpu.emscripten_webgpu_get_device();
        log("Device: {*}\n", .{device});
    } else {
        if (builtin.os.tag == .macos) {
            const metal_layer = objc.getMetalLayer(glfw.getCocoaWindow(window).?);
            log("\nMetal Layer: {any}", .{metal_layer});

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
            log("Surface: {any}\n", .{surface});
            std.debug.assert(surface != null);
        }
        if (builtin.os.tag == .windows) {
            var wgpu_surface_source_windows_hwnd = wgpu.WGPUSurfaceSourceWindowsHWND{
                .chain = wgpu.WGPUChainedStruct{
                    .sType = wgpu.WGPUSType_SurfaceSourceWindowsHWND,
                },
                .hinstance = std.os.windows.kernel32.GetModuleHandleW(null).?,
                .hwnd = glfw.getWin32Window(window),
            };
            surface = wgpu.wgpuInstanceCreateSurface(instance, &wgpu.WGPUSurfaceDescriptor{
                .label = wgpu.WGPUStringView{
                    .data = "Surface/Windows",
                    .length = wgpu.WGPU_STRLEN,
                },
                .nextInChain = @ptrCast(&wgpu_surface_source_windows_hwnd),
            });
            log("\nSurface: {any}", .{surface});
            std.debug.assert(surface != null);
        }

        var request_adatper_userdata = RequestAdapterUserData{};
        _ = wgpu.wgpuInstanceRequestAdapter(
            instance,
            &wgpu.WGPURequestAdapterOptions{
                .compatibleSurface = surface, // null for headless
            },
            wgpu.WGPURequestAdapterCallbackInfo{
                .mode = wgpu.WGPUCallbackMode_AllowSpontaneous,
                .callback = handleRequestAdapter,
                .userdata1 = &request_adatper_userdata,
            },
        );
        adapter = request_adatper_userdata.adapter;
        log("Adapter: {*}\n", .{adapter});
        std.debug.assert(adapter != null);
        printAdapterInfo();

        var request_device_userdata = RequestDeviceUserData{};
        _ = wgpu.wgpuAdapterRequestDevice(
            adapter,
            null,
            wgpu.WGPURequestDeviceCallbackInfo{
                .mode = wgpu.WGPUCallbackMode_AllowSpontaneous,
                .callback = handleRequestDevice,
                .userdata1 = &request_device_userdata,
            },
        );
        device = request_device_userdata.device;
        log("Device: {*}\n", .{device});
        std.debug.assert(device != null);
    }

    queue = wgpu.wgpuDeviceGetQueue(device);
    log("Queue: {*}\n", .{queue});
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
        log("Surface: {*}\n", .{surface});

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

        texture_format = if (builtin.os.tag == .emscripten) wgpu.WGPUTextureFormat_BGRA8Unorm else capabilities.formats[0];

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
}

fn createShaderModule(shader_code: []const u8) wgpu.WGPUShaderModule {
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
    log("Shader: {*}\n", .{shader_module});
    std.debug.assert(shader_module != null);
    return shader_module;
}

fn renderPipeline() void {
    // SHADER
    const shader_module = createShaderModule(@embedFile("@render.basic"));

    // Pixel buffer
    pixel_buffer = createBuffer(
        u32,
        "Pixel Buffer",
        width * height,
        wgpu.WGPUBufferUsage_MapRead | wgpu.WGPUBufferUsage_CopyDst,
    );

    // Uniform buffer
    uniform_buffer = createBuffer(
        Uniforms,
        "Uniform Buffer",
        1,
        wgpu.WGPUBufferUsage_Uniform,
    );
    std.debug.assert(uniform_buffer != null);
    log("Uniform Buffer: {any}\n", .{uniform_buffer});

    const vertex_attributes_auto = createVertexAttributes(Vertex);
    log("\n\nVertex Attributes: {any}\n", .{vertex_attributes_auto});

    const vertex_buffer_layout = wgpu.WGPUVertexBufferLayout{
        .arrayStride = @sizeOf(Vertex),
        .stepMode = wgpu.WGPUVertexStepMode_Vertex,
        .attributeCount = vertex_attributes_auto.len,
        .attributes = &vertex_attributes_auto,
    };
    log("\n\nVertex Buffer Layout: {any}\n", .{vertex_buffer_layout});

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
    log("Bind Group: {any}\n", .{bind_group});

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
                .targetCount = 2,
                .targets = &[_]wgpu.WGPUColorTargetState{
                    wgpu.WGPUColorTargetState{
                        .format = wgpu.WGPUTextureFormat_RGBA8Unorm,
                        .writeMask = wgpu.WGPUColorWriteMask_All,
                    },
                    wgpu.WGPUColorTargetState{
                        .format = texture_format,
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
    log("Render Pipeline: {*}\n", .{render_pipeline});

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
    log("Vertex + Index Buffer:\n{any}\n{any}\n", .{ vertex_buffer, index_buffer });
}

fn computePipeline() void {
    // Data
    const amount = 24;
    var numbers = [_]u32{1} ** amount;
    for (0..amount) |i| {
        numbers[i] = @intCast(i);
    }
    const numbers_size = @sizeOf(@TypeOf(numbers));

    // Buffers
    const input_buffer = createBuffer(
        u32,
        "Input Buffer",
        numbers.len,
        wgpu.WGPUBufferUsage_Storage,
    );

    const output_buffer = createBuffer(
        u32,
        "Output Buffer",
        numbers.len,
        wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopySrc,
    );

    const map_buffer = createBuffer(
        u32,
        "Mapping Buffer",
        numbers.len,
        wgpu.WGPUBufferUsage_MapRead,
    );

    // Bind group
    const bind_group_layout_entries = &[_]wgpu.WGPUBindGroupLayoutEntry{
        wgpu.WGPUBindGroupLayoutEntry{
            .binding = 0,
            .visibility = wgpu.WGPUShaderStage_Compute,
            .buffer = wgpu.WGPUBufferBindingLayout{
                .type = wgpu.WGPUBufferBindingType_ReadOnlyStorage,
                .hasDynamicOffset = @intFromBool(false),
            },
        },
        wgpu.WGPUBindGroupLayoutEntry{
            .binding = 1,
            .visibility = wgpu.WGPUShaderStage_Compute,
            .buffer = wgpu.WGPUBufferBindingLayout{
                .type = wgpu.WGPUBufferBindingType_Storage,
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
            .buffer = input_buffer,
            .offset = 0,
            .size = numbers_size,
        },
        wgpu.WGPUBindGroupEntry{
            .binding = 1,
            .buffer = output_buffer,
            .offset = 0,
            .size = numbers_size,
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

    // Shader
    const compute_shader = createShaderModule(@embedFile("@compute.basic"));

    const pipeline_layout = wgpu.wgpuDeviceCreatePipelineLayout(
        device,
        &wgpu.WGPUPipelineLayoutDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Compute Pipeline Layout",
                .length = wgpu.WGPU_STRLEN,
            },
            .bindGroupLayoutCount = 1,
            .bindGroupLayouts = &bind_group_layout,
        },
    );
    const compute_pipeline = wgpu.wgpuDeviceCreateComputePipeline(
        device,
        &wgpu.WGPUComputePipelineDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Compute Pipeline",
                .length = wgpu.WGPU_STRLEN,
            },
            .layout = pipeline_layout,
            .compute = (if (builtin.os.tag == .emscripten) wgpu.WGPUComputeState else wgpu.WGPUProgrammableStageDescriptor){
                .module = compute_shader,
                .entryPoint = wgpu.WGPUStringView{
                    .data = "main",
                    .length = wgpu.WGPU_STRLEN,
                },
            },
        },
    );
    std.debug.assert(compute_pipeline != null);

    // Dispatch
    const buffer_size = @sizeOf(@TypeOf(numbers));
    const command_encoder = wgpu.wgpuDeviceCreateCommandEncoder(
        device,
        &wgpu.WGPUCommandEncoderDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Compute Command Encoder",
                .length = wgpu.WGPU_STRLEN,
            },
        },
    );

    const compute_pass_encoder = wgpu.wgpuCommandEncoderBeginComputePass(
        command_encoder,
        &wgpu.WGPUComputePassDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Compute Pass",
                .length = wgpu.WGPU_STRLEN,
            },
        },
    );

    wgpu.wgpuComputePassEncoderSetPipeline(compute_pass_encoder, compute_pipeline);
    wgpu.wgpuComputePassEncoderSetBindGroup(compute_pass_encoder, 0, bind_group, 0, 0);

    const dispatch_count = (numbers.len / 16) + 1;
    wgpu.wgpuComputePassEncoderDispatchWorkgroups(compute_pass_encoder, dispatch_count, 1, 1);

    wgpu.wgpuComputePassEncoderEnd(compute_pass_encoder);

    // oputput buffer → mapping buffer
    wgpu.wgpuCommandEncoderCopyBufferToBuffer(
        command_encoder,
        output_buffer,
        0,
        map_buffer,
        0,
        buffer_size,
    );

    const command_buffer = wgpu.wgpuCommandEncoderFinish(
        command_encoder,
        &wgpu.WGPUCommandBufferDescriptor{
            .label = wgpu.WGPUStringView{
                .data = "Compute Command Buffer",
                .length = wgpu.WGPU_STRLEN,
            },
        },
    );
    std.debug.assert(command_buffer != null);

    // Upload data
    wgpu.wgpuQueueWriteBuffer(
        queue,
        input_buffer,
        0,
        &numbers,
        buffer_size,
    );
    wgpu.wgpuQueueSubmit(queue, 1, &command_buffer);

    // Retrieve results
    var user_data = MappedBufferUserData{};
    _ = wgpu.wgpuBufferMapAsync(
        map_buffer,
        wgpu.WGPUMapMode_Read,
        0,
        buffer_size,
        wgpu.WGPUBufferMapCallbackInfo{
            .mode = wgpu.WGPUCallbackMode_AllowSpontaneous,
            .callback = handleMappedBuffer,
            .userdata1 = &user_data,
        },
    );

    while (!user_data.done) {
        if (builtin.os.tag == .emscripten) {
            log("Sleeping... \n", .{});
            emsc.emscripten_sleep(100);
        }
        wgpu.wgpuInstanceProcessEvents(instance);
    }

    const result = @as([*]const u32, @ptrCast(@alignCast(wgpu.wgpuBufferGetConstMappedRange(
        map_buffer,
        0,
        buffer_size,
    ))));

    wgpu.wgpuBufferUnmap(map_buffer);

    log("Compute Results:", .{});
    for (0..amount) |i| {
        log("\n{d: >4}: {d: >4}", .{ numbers[i], result[i] });
    }

    // Cleanup
    wgpu.wgpuComputePassEncoderRelease(compute_pass_encoder);
    wgpu.wgpuCommandBufferRelease(command_buffer);
    wgpu.wgpuCommandEncoderRelease(command_encoder);
}

fn compute() void {}

fn deinit() void {
    wgpu.wgpuQueueRelease(queue);
    wgpu.wgpuInstanceRelease(instance);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    zstbi.init(allocator);
    zstbi.setFlipVerticallyOnWrite(true);
    defer zstbi.deinit();

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.CLIENT_API, .NO_API);
    window = glfw.createWindow(width, height, "[wgpu-native + glfw]", null);

    try setup();

    target_texture = createTexture();
    std.debug.print("Texture: {any}\n", .{target_texture});
    std.debug.assert(target_texture != null);
    target_texture_view = createTextureView(target_texture);
    std.debug.print("Texture View: {any}\n", .{target_texture_view});
    std.debug.assert(target_texture_view != null);

    // computePipeline();

    renderPipeline();

    if (builtin.os.tag == .emscripten) {
        emsc.emscripten_set_main_loop(draw, 0, true);
    } else {
        while (!glfw.shouldClose(window)) {
            if (glfw.getKey(window, .escape) == .press) break;
            glfw.pollEvents();

            draw();

            if (frame_number > record_frame_count) break;
            frame_number += 1;
        }

        // headless: {
        //     var frame: usize = 0;
        //     while (true) : (frame += 1) {
        //         if (frame > 100) break;
        //         std.debug.print("Writing frame {d:0>4}\n", .{frame});
        //         draw();
        //     }
        //     break :headless;
        // }
    }

    // const w: usize = 128;
    // const h: usize = 128;
    // const channels: usize = 4;
    // var pixels = [_]u8{0} ** (w * h * channels);
    // var i: usize = 0;
    // while (i < pixels.len) : (i += channels) {
    //     pixels[i + 0] = 255;
    //     pixels[i + 1] = 0;
    //     pixels[i + 2] = 0;
    //     pixels[i + 3] = 255;
    // }

    deinit();
}

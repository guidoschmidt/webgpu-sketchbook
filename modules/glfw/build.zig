const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("glfw", .{
        .root_source_file = b.path("./src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const env_map = try b.allocator.create(std.process.EnvMap);
    env_map.* = try std.process.getEnvMap(b.allocator);
    const vulkan_sdk = env_map.get("VULKAN_SDK");
    if (vulkan_sdk == null) {
        std.log.err("\nPlease set VULKAN_SDK!", .{});
    }
    const include_path = b.pathJoin(&.{ vulkan_sdk.?, "include" });
    std.debug.print("\nVulkan SDK: {s}", .{include_path});

    module.addSystemIncludePath(.{
        .cwd_relative = include_path,
    });

    module.addLibraryPath(b.path("./libs/"));
    module.addIncludePath(b.path("./libs/"));

    if (target.result.os.tag != .emscripten) {
        module.linkSystemLibrary("glfw3", .{});
    }
}

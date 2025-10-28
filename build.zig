const std = @import("std");
const builtin = @import("builtin");

pub fn compileShader(
    b: *std.Build,
    targets: []const *std.Build.Step.Compile,
    name: []const u8,
    entry: ?[]const u8,
    input_filepath: []const u8,
    output_filepath: []const u8,
) !void {
    var buf: [256]u8 = undefined;
    const step_name = try std.fmt.bufPrint(&buf, "Compile shader {s}", .{name});
    const shader_step = b.step(step_name, "Compile shader code");

    const slangc = b.addSystemCommand(&.{"slangc"});
    slangc.addFileArg(b.path(input_filepath));

    slangc.addArg("-target");
    slangc.addArg("wgsl");
    if (entry) |e| {
        slangc.addArg("-entry");
        slangc.addArg(e);
    }
    slangc.addArg("-o");

    const output_path = slangc.addOutputFileArg(output_filepath);

    std.debug.print("\nCompiling shader {s}: {any}", .{ name, output_path });

    // Copy the file from cache to source tree
    const usf = b.addUpdateSourceFiles();
    usf.addCopyFileToSource(output_path, output_filepath);

    // Update build graph
    shader_step.dependOn(&usf.step);

    for (targets) |target| {
        target.root_module.addAnonymousImport(name, .{
            .root_source_file = output_path,
        });
    }
}

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const src_path = "src/main.zig";
    var compile: *std.Build.Step.Compile = undefined;

    const glfw_dep = b.dependency("glfw", .{
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag != .emscripten) {
        const module = b.createModule(.{
            .root_source_file = b.path(src_path),
            .target = target,
            .optimize = optimize,
        });
        const exe = b.addExecutable(.{
            .name = "exe",
            .root_module = module,
        });
        compile = exe;

        exe.addLibraryPath(glfw_dep.path("libs"));
        exe.root_module.addImport("glfw", glfw_dep.module("glfw"));

        // webgpu-headers
        // :warning: This is using an older version of the headers
        // commit bac520839ff5ed2e2b648ed540bd9ec45edbccbc
        // as wgpu-native is not up-to-date with webgpu-headers
        // https://github.com/gfx-rs/wgpu-native/pull/511
        const wgpu_headers_dep = b.lazyDependency("wgpu_headers", .{}) orelse @panic("Can't find dependency");
        module.addIncludePath(wgpu_headers_dep.path("./"));

        std.debug.print("\n⚠ Compiling for macOS\n\n", .{});
        const wgpu_native_dep = b.lazyDependency("wgpu_macos_aarch64_debug", .{}) orelse @panic("Can't find dependency");
        const prefix = "lib";
        const extension = "a";
        const lib_name = b.fmt("lib/{s}wgpu_native.{s}", .{ prefix, extension });
        const wgpu_native_lib = wgpu_native_dep.path(lib_name);
        module.addObjectFile(wgpu_native_lib);

        module.linkFramework("Foundation", .{});
        module.linkFramework("QuartzCore", .{});
        module.linkFramework("Metal", .{});
        module.linkFramework("CoreGraphics", .{});
        module.linkSystemLibrary("objc", .{});

        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    if (target.result.os.tag == .emscripten) {
        const emscripten_lib = b.addLibrary(.{
            .linkage = .static,
            .name = "lib",
            .root_module = b.createModule(.{
                .root_source_file = b.path(src_path),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        emscripten_lib.root_module.addImport("glfw", glfw_dep.module("glfw"));
        compile = emscripten_lib;

        const env_map = try b.allocator.create(std.process.EnvMap);
        env_map.* = try std.process.getEnvMap(b.allocator);
        const sysroot = env_map.get("EMSDK_PATH");

        if (sysroot == null) {
            std.log.err(
                \\Please set EMSDK_PATH env variable!
                \\e.g. on fish shell: 'set -UX EMSDK_PATH /opt/homebrew/Cellar/emscripten/4.0.13/'
            , .{});
            return error.Wasm32SysRootExpected;
        }
        emscripten_lib.addSystemIncludePath(.{
            .cwd_relative = b.pathJoin(&.{
                sysroot.?,
                "libexec",
                "cache",
                // "sysroot",
                // "include",
                "ports",
                "emdawnwebgpu",
                "emdawnwebgpu_pkg",
                "webgpu",
                "include",
            }),
        });

        emscripten_lib.addSystemIncludePath(.{
            .cwd_relative = b.pathJoin(&.{
                sysroot.?,
                "libexec",
                "cache",
                "sysroot",
                "include",
            }),
        });

        const emcc_exe = switch (builtin.os.tag) {
            .windows => "emcc.bat",
            else => "emcc",
        };

        const emcc_cmd = b.addSystemCommand(&[_][]const u8{emcc_exe});
        emcc_cmd.addFileArg(emscripten_lib.getEmittedBin());
        emcc_cmd.addArgs(&[_][]const u8{
            "-o",
            "zig-out/web/index.html",
            "-Oz",
            "--shell-file=src/html/shell.html",
            "--closure=1",
            "-sASYNCIFY",
            "-sUSE_GLFW=3",
            // "-sALLOW_MEMORY_GROWTH=1",
            // "-sMALLOC=emmalloc",
            "--use-port=emdawnwebgpu:cpp_bindings=false",
            // "--use-port=./emdawnwebgpu-v20250820.224631.remoteport.py:cpp_bindings=false",
        });
        emcc_cmd.step.dependOn(&emscripten_lib.step);

        if (optimize == .Debug or optimize == .ReleaseSafe) {
            emcc_cmd.addArgs(&[_][]const u8{
                // "-sUSE_OFFSET_CONVERTER",
                "-sASSERTIONS",
            });
        }

        b.getInstallStep().dependOn(&emcc_cmd.step);

        const serve_step = b.step("run", "Serve the web page");
        serve_step.dependOn(&emscripten_lib.step);

        const serve = b.addSystemCommand(&.{"bunx"});
        serve.addArg("http-server");
        serve.addArg("--cors");

        serve_step.dependOn(&serve.step);
    }

    // Shaders
    try compileShader(
        b,
        &.{compile},
        "@compute.basic",
        null,
        "src/slang/compute.slang",
        "src/shader/wgsl/compute.wgsl",
    );
    try compileShader(
        b,
        &.{compile},
        "@render.basic",
        null,
        "src/slang/basic.slang",
        "src/shader/wgsl/basic.wgsl",
    );
}

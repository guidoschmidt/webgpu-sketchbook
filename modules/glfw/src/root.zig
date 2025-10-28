const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    // Prevent GLFW from loading the OpenGL header
    @cDefine("GLFW_INCLUDE_NONE", {});
    // Make GLFW include the Vulkan header
    // @cInclude("vulkan/vulkan.h");
    if (builtin.os.tag == .macos) {
        @cDefine("GLFW_EXPOSE_NATIVE_COCOA", {});
    }
    if (builtin.os.tag == .windows) {
        @cDefine("GLFW_EXPOSE_NATIVE_WIN32", {});
    }
    @cInclude("GLFW/glfw3.h");
    if (builtin.os.tag != .emscripten) {
        @cInclude("GLFW/glfw3native.h");
    }
});

pub const Window = c.GLFWwindow;
pub const Monitor = c.GLFWmonitor;
pub const getInstanceProcAddress = c.glfwGetInstanceProcAddress;
pub const getRequiredInstanceExtensions = c.glfwGetRequiredInstanceExtensions;

pub const GlfwError = error{
    InitializationFailed,
};

pub fn init() !void {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return GlfwError.InitializationFailed;
    }
}

pub fn createWindow(
    width: usize,
    height: usize,
    name: []const u8,
    monitor: ?*Monitor,
) *Window {
    return @ptrCast(c.glfwCreateWindow(
        @intCast(width),
        @intCast(height),
        @ptrCast(name.ptr),
        monitor,
        null,
    ));
}

pub fn destroyWindow(window: *Window) void {
    c.glfwDestroyWindow(window);
}

pub fn terminate() void {
    return c.glfwTerminate();
}

pub fn pollEvents() void {
    c.glfwPollEvents();
}

pub fn shouldClose(window: *Window) bool {
    return c.glfwWindowShouldClose(@ptrCast(window)) == c.GLFW_TRUE;
}

pub fn isVulkanSupported() bool {
    return c.glfwVulkanSupported() == c.GLFW_TRUE;
}

pub fn getKey(window: *Window, key: Key) Action {
    return @enumFromInt(c.glfwGetKey(window, @intFromEnum(key)));
}

/// Key and button actions
pub const Action = enum(c_int) {
    /// The key or mouse button was released.
    release = c.GLFW_RELEASE,
    /// The key or mouse button was pressed.
    press = c.GLFW_PRESS,
    /// The key was held down until it repeated.
    repeat = c.GLFW_REPEAT,
};

pub const Key = enum(c_int) {
    /// The unknown key
    unknown = c.GLFW_KEY_UNKNOWN,

    /// Printable keys
    space = c.GLFW_KEY_SPACE,
    apostrophe = c.GLFW_KEY_APOSTROPHE,
    comma = c.GLFW_KEY_COMMA,
    minus = c.GLFW_KEY_MINUS,
    period = c.GLFW_KEY_PERIOD,
    slash = c.GLFW_KEY_SLASH,
    zero = c.GLFW_KEY_0,
    one = c.GLFW_KEY_1,
    two = c.GLFW_KEY_2,
    three = c.GLFW_KEY_3,
    four = c.GLFW_KEY_4,
    five = c.GLFW_KEY_5,
    six = c.GLFW_KEY_6,
    seven = c.GLFW_KEY_7,
    eight = c.GLFW_KEY_8,
    nine = c.GLFW_KEY_9,
    semicolon = c.GLFW_KEY_SEMICOLON,
    equal = c.GLFW_KEY_EQUAL,
    a = c.GLFW_KEY_A,
    b = c.GLFW_KEY_B,
    c = c.GLFW_KEY_C,
    d = c.GLFW_KEY_D,
    e = c.GLFW_KEY_E,
    f = c.GLFW_KEY_F,
    g = c.GLFW_KEY_G,
    h = c.GLFW_KEY_H,
    i = c.GLFW_KEY_I,
    j = c.GLFW_KEY_J,
    k = c.GLFW_KEY_K,
    l = c.GLFW_KEY_L,
    m = c.GLFW_KEY_M,
    n = c.GLFW_KEY_N,
    o = c.GLFW_KEY_O,
    p = c.GLFW_KEY_P,
    q = c.GLFW_KEY_Q,
    r = c.GLFW_KEY_R,
    s = c.GLFW_KEY_S,
    t = c.GLFW_KEY_T,
    u = c.GLFW_KEY_U,
    v = c.GLFW_KEY_V,
    w = c.GLFW_KEY_W,
    x = c.GLFW_KEY_X,
    y = c.GLFW_KEY_Y,
    z = c.GLFW_KEY_Z,
    left_bracket = c.GLFW_KEY_LEFT_BRACKET,
    backslash = c.GLFW_KEY_BACKSLASH,
    right_bracket = c.GLFW_KEY_RIGHT_BRACKET,
    // grave_acent = c.GLFW_KEY_GRAVE_ACENT,
    world_1 = c.GLFW_KEY_WORLD_1, // non-US #1
    world_2 = c.GLFW_KEY_WORLD_2, // non-US #2

    // Function keys
    escape = c.GLFW_KEY_ESCAPE,
    enter = c.GLFW_KEY_ENTER,
    tab = c.GLFW_KEY_TAB,
    backspace = c.GLFW_KEY_BACKSPACE,
    insert = c.GLFW_KEY_INSERT,
    delete = c.GLFW_KEY_DELETE,
    right = c.GLFW_KEY_RIGHT,
    left = c.GLFW_KEY_LEFT,
    down = c.GLFW_KEY_DOWN,
    up = c.GLFW_KEY_UP,
    page_up = c.GLFW_KEY_PAGE_UP,
    page_down = c.GLFW_KEY_PAGE_DOWN,
    home = c.GLFW_KEY_HOME,
    end = c.GLFW_KEY_END,
    caps_lock = c.GLFW_KEY_CAPS_LOCK,
    scroll_lock = c.GLFW_KEY_SCROLL_LOCK,
    num_lock = c.GLFW_KEY_NUM_LOCK,
    print_screen = c.GLFW_KEY_PRINT_SCREEN,
    pause = c.GLFW_KEY_PAUSE,
    F1 = c.GLFW_KEY_F1,
    F2 = c.GLFW_KEY_F2,
    F3 = c.GLFW_KEY_F3,
    F4 = c.GLFW_KEY_F4,
    F5 = c.GLFW_KEY_F5,
    F6 = c.GLFW_KEY_F6,
    F7 = c.GLFW_KEY_F7,
    F8 = c.GLFW_KEY_F8,
    F9 = c.GLFW_KEY_F9,
    F10 = c.GLFW_KEY_F10,
    F11 = c.GLFW_KEY_F11,
    F12 = c.GLFW_KEY_F12,
    F13 = c.GLFW_KEY_F13,
    F14 = c.GLFW_KEY_F14,
    F15 = c.GLFW_KEY_F15,
    F16 = c.GLFW_KEY_F16,
    F17 = c.GLFW_KEY_F17,
    F18 = c.GLFW_KEY_F18,
    F19 = c.GLFW_KEY_F19,
    F20 = c.GLFW_KEY_F20,
    F21 = c.GLFW_KEY_F21,
    F22 = c.GLFW_KEY_F22,
    F23 = c.GLFW_KEY_F23,
    F24 = c.GLFW_KEY_F24,
    F25 = c.GLFW_KEY_F25,
    kp_0 = c.GLFW_KEY_KP_0,
    kp_1 = c.GLFW_KEY_KP_1,
    kp_2 = c.GLFW_KEY_KP_2,
    kp_3 = c.GLFW_KEY_KP_3,
    kp_4 = c.GLFW_KEY_KP_4,
    kp_5 = c.GLFW_KEY_KP_5,
    kp_6 = c.GLFW_KEY_KP_6,
    kp_7 = c.GLFW_KEY_KP_7,
    kp_8 = c.GLFW_KEY_KP_8,
    kp_9 = c.GLFW_KEY_KP_9,
    kp_decimal = c.GLFW_KEY_KP_DECIMAL,
    kp_divide = c.GLFW_KEY_KP_DIVIDE,
    kp_multiply = c.GLFW_KEY_KP_MULTIPLY,
    kp_subtract = c.GLFW_KEY_KP_SUBTRACT,
    kp_add = c.GLFW_KEY_KP_ADD,
    kp_enter = c.GLFW_KEY_KP_ENTER,
    kp_equal = c.GLFW_KEY_KP_EQUAL,
    left_shift = c.GLFW_KEY_LEFT_SHIFT,
    left_control = c.GLFW_KEY_LEFT_CONTROL,
    left_alt = c.GLFW_KEY_LEFT_ALT,
    left_super = c.GLFW_KEY_LEFT_SUPER,
    right_shift = c.GLFW_KEY_RIGHT_SHIFT,
    right_control = c.GLFW_KEY_RIGHT_CONTROL,
    right_alt = c.GLFW_KEY_RIGHT_ALT,
    right_super = c.GLFW_KEY_RIGHT_SUPER,
    menu = c.GLFW_KEY_MENU,

    pub inline fn last() Key {
        return @as(Key, @enumFromInt(c.GLFW_KEY_LAST));
    }

    /// Returns the layout-specific name of the specified printable key.
    ///
    /// This function returns the name of the specified printable key, encoded as UTF-8. This is
    /// typically the character that key would produce without any modifier keys, intended for
    /// displaying key bindings to the user. For dead keys, it is typically the diacritic it would add
    /// to a character.
    ///
    /// __Do not use this function__ for text input (see input_char). You will break text input for many
    /// languages even if it happens to work for yours.
    ///
    /// If the key is `glfw.key.unknown`, the scancode is used to identify the key, otherwise the
    /// scancode is ignored. If you specify a non-printable key, or `glfw.key.unknown` and a scancode
    /// that maps to a non-printable key, this function returns null but does not emit an error.
    ///
    /// This behavior allows you to always pass in the arguments in the key callback (see input_key)
    /// without modification.
    ///
    /// The printable keys are:
    ///
    /// - `glfw.Key.apostrophe`
    /// - `glfw.Key.comma`
    /// - `glfw.Key.minus`
    /// - `glfw.Key.period`
    /// - `glfw.Key.slash`
    /// - `glfw.Key.semicolon`
    /// - `glfw.Key.equal`
    /// - `glfw.Key.left_bracket`
    /// - `glfw.Key.right_bracket`
    /// - `glfw.Key.backslash`
    /// - `glfw.Key.world_1`
    /// - `glfw.Key.world_2`
    /// - `glfw.Key.0` to `glfw.key.9`
    /// - `glfw.Key.a` to `glfw.key.z`
    /// - `glfw.Key.kp_0` to `glfw.key.kp_9`
    /// - `glfw.Key.kp_decimal`
    /// - `glfw.Key.kp_divide`
    /// - `glfw.Key.kp_multiply`
    /// - `glfw.Key.kp_subtract`
    /// - `glfw.Key.kp_add`
    /// - `glfw.Key.kp_equal`
    ///
    /// Names for printable keys depend on keyboard layout, while names for non-printable keys are the
    /// same across layouts but depend on the application language and should be localized along with
    /// other user interface text.
    ///
    /// @param[in] key The key to query, or `glfw.key.unknown`.
    /// @param[in] scancode The scancode of the key to query.
    /// @return The UTF-8 encoded, layout-specific name of the key, or null.
    ///
    /// Possible errors include glfw.ErrorCode.PlatformError.
    /// Also returns null in the event of an error.
    ///
    /// The contents of the returned string may change when a keyboard layout change event is received.
    ///
    /// @pointer_lifetime The returned string is allocated and freed by GLFW. You should not free it
    /// yourself. It is valid until the library is terminated.
    ///
    /// @thread_safety This function must only be called from the main thread.
    ///
    /// see also: input_key_name
    pub inline fn getName(self: Key, scancode: i32) ?[:0]const u8 {
        // internal_debug.assertInitialized();
        const name_opt = c.glfwGetKeyName(@intFromEnum(self), @intCast(scancode));
        return if (name_opt) |name|
            std.mem.span(@ptrCast(name))
        else
            null;
    }

    /// Returns the platform-specific scancode of the specified key.
    ///
    /// This function returns the platform-specific scancode of the specified key.
    ///
    /// If the key is `glfw.key.UNKNOWN` or does not exist on the keyboard this method will return `-1`.
    ///
    /// @param[in] key Any named key (see keys).
    /// @return The platform-specific scancode for the key.
    ///
    /// Possible errors include glfw.ErrorCode.InvalidEnum and glfw.ErrorCode.PlatformError.
    /// Additionally returns -1 in the event of an error.
    ///
    /// @thread_safety This function may be called from any thread.
    pub inline fn getScancode(self: Key) i32 {
        // internal_debug.assertInitialized();
        return c.glfwGetKeyScancode(@intFromEnum(self));
    }
};

const WINDOW_HINT = enum(c_int) {
    CLIENT_API = c.GLFW_CLIENT_API,
};

const WINDOW_HINT_VALUE = enum(c_int) {
    NO_API = c.GLFW_NO_API,
};

pub fn windowHint(hint: WINDOW_HINT, value: WINDOW_HINT_VALUE) void {
    c.glfwWindowHint(@intFromEnum(hint), @intFromEnum(value));
}

pub fn frameBufferSize(window: *Window, width: *c_int, height: *c_int) void {
    c.glfwGetFramebufferSize(window, width, height);
}

pub fn moveWindow(window: *Window, x: usize, y: usize) void {
    c.glfwSetWindowPos(window, @intCast(x), @intCast(y));
}

pub fn setFramebufferResizeCallback(
    window: *Window,
    callback: fn (window: ?*Window, width: c_int, height: c_int) callconv(.c) void,
) void {
    _ = c.glfwSetFramebufferSizeCallback(window, callback);
}

pub fn getPrimaryMonitor() *Monitor {
    return c.glfwGetPrimaryMonitor().?;
}

pub fn getCocoaWindow(window: *Window) ?*anyopaque {
    if (builtin.target.os.tag == .macos) {
        return c.glfwGetCocoaWindow(window);
    }
    return null;
}

pub fn getWin32Window(window: *Window) ?*anyopaque {
    if (builtin.target.os.tag == .windows) {
        return c.glfwGetWin32Window(window);
    }
    return null;
}

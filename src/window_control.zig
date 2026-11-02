const std = @import("std");
const nanoui = @import("nanoui");
const objc = nanoui.objc;
const layout = @import("window_layout.zig");
const Ref = *const anyopaque;

extern "c" fn AXIsProcessTrusted() u8;
extern "c" fn AXIsProcessTrustedWithOptions(options: Ref) u8;
extern const kAXTrustedCheckOptionPrompt: Ref;
extern "c" fn AXUIElementCreateApplication(pid: i32) ?Ref;
extern "c" fn AXUIElementCopyAttributeValue(element: Ref, attribute: Ref, value: *?Ref) i32;
extern "c" fn AXUIElementSetAttributeValue(element: Ref, attribute: Ref, value: Ref) i32;
extern "c" fn AXUIElementIsAttributeSettable(element: Ref, attribute: Ref, settable: *u8) i32;
extern "c" fn AXUIElementSetMessagingTimeout(element: Ref, seconds: f32) i32;
extern "c" fn AXUIElementPerformAction(element: Ref, action: Ref) i32;
extern "c" fn AXUIElementGetTypeID() usize;
extern "c" fn AXValueCreate(kind: u32, value: *const anyopaque) ?Ref;
extern "c" fn AXValueGetTypeID() usize;
extern "c" fn AXValueGetValue(value: Ref, kind: u32, out: *anyopaque) u8;
extern "c" fn CFGetTypeID(value: Ref) usize;
extern "c" fn CFRetain(value: Ref) Ref;
extern "c" fn CFRelease(value: Ref) void;
extern "c" fn CFEqual(a: Ref, b: Ref) u8;
extern "c" fn CFBooleanGetTypeID() usize;
extern "c" fn CFBooleanGetValue(value: Ref) u8;

pub const Manager = struct {
    pid: i32 = 0,
    window: ?Ref = null,
    saved: [32]?Saved = @splat(null),
    next: usize = 0,
    prompted: bool = false,

    const Saved = struct { window: Ref, frame: layout.Rect };

    pub fn deinit(manager: *Manager) void {
        if (manager.window) |window| CFRelease(window);
        for (manager.saved) |saved| if (saved) |entry| CFRelease(entry.window);
        manager.* = .{};
    }

    pub fn capture(manager: *Manager) void {
        const pool = objc.Pool.push();
        defer pool.pop();
        const workspace = objc.msg(objc.Object, objc.class("NSWorkspace"), "sharedWorkspace", .{});
        const app = objc.msg(?objc.Object, workspace, "frontmostApplication", .{}) orelse return;
        const pid = objc.msg(i32, app, "processIdentifier", .{});
        const me = objc.msg(objc.Object, objc.class("NSRunningApplication"), "currentApplication", .{});
        if (pid == objc.msg(i32, me, "processIdentifier", .{})) return;
        if (manager.window) |window| CFRelease(window);
        manager.pid = pid;
        manager.window = if (AXIsProcessTrusted() != 0) focused(pid) else null;
    }

    pub fn run(manager: *Manager, action: layout.Action) layout.Failure!void {
        const pool = objc.Pool.push();
        defer pool.pop();
        if (AXIsProcessTrusted() == 0) {
            if (!manager.prompted) {
                manager.prompted = true;
                const yes = objc.msg(objc.Object, objc.class("NSNumber"), "numberWithBool:", .{objc.YES});
                const key: objc.Object = @ptrCast(@constCast(kAXTrustedCheckOptionPrompt));
                const options = objc.msg(objc.Object, objc.class("NSDictionary"), "dictionaryWithObject:forKey:", .{ yes, key });
                _ = AXIsProcessTrustedWithOptions(options);
            }
            return error.AccessibilityRequired;
        }
        if (manager.pid <= 0) return error.NoWindow;
        if (manager.window == null) manager.window = focused(manager.pid);
        const window = manager.window orelse return error.NoWindow;
        if (boolean(window, "AXFullScreen")) return error.FullscreenWindow;
        const before = try frame(window);
        var display_buf: [32]layout.Display = undefined;
        const displays = screens(&display_buf);
        const index = manager.find(window);
        const original = if (index) |i| manager.saved[i].?.frame else null;
        const destination = try layout.target(action, before, displays, original);
        apply(window, before, destination) catch |err| {
            apply(window, destination, before) catch {};
            return err;
        };
        if (action == .restore) {
            if (index) |i| {
                CFRelease(manager.saved[i].?.window);
                manager.saved[i] = null;
            }
        } else if (index == null) {
            if (manager.saved[manager.next]) |entry| CFRelease(entry.window);
            manager.saved[manager.next] = .{ .window = CFRetain(window), .frame = before };
            manager.next = (manager.next + 1) % manager.saved.len;
        }
        _ = AXUIElementPerformAction(window, objc.nsString("AXRaise"));
        const app = objc.msg(?objc.Object, objc.class("NSRunningApplication"), "runningApplicationWithProcessIdentifier:", .{manager.pid}) orelse return;
        _ = objc.msg(objc.BOOL, app, "activateWithOptions:", .{@as(objc.NSUInteger, 2)});
    }

    fn find(manager: *const Manager, window: Ref) ?usize {
        for (manager.saved, 0..) |saved, i| if (saved) |entry| {
            if (CFEqual(entry.window, window) != 0) return i;
        };
        return null;
    }
};

fn attribute(element: Ref, name: []const u8) ?Ref {
    var value: ?Ref = null;
    if (AXUIElementCopyAttributeValue(element, objc.nsString(name), &value) != 0) return null;
    return value;
}

fn boolean(element: Ref, name: []const u8) bool {
    const value = attribute(element, name) orelse return false;
    defer CFRelease(value);
    return CFGetTypeID(value) == CFBooleanGetTypeID() and CFBooleanGetValue(value) != 0;
}

fn focused(pid: i32) ?Ref {
    const app = AXUIElementCreateApplication(pid) orelse return null;
    defer CFRelease(app);
    _ = AXUIElementSetMessagingTimeout(app, 0.3);
    const window = attribute(app, "AXFocusedWindow") orelse return null;
    if (CFGetTypeID(window) != AXUIElementGetTypeID()) {
        CFRelease(window);
        return null;
    }
    _ = AXUIElementSetMessagingTimeout(window, 0.3);
    return window;
}

fn frame(window: Ref) layout.Failure!layout.Rect {
    const position = attribute(window, "AXPosition") orelse return error.WindowUnavailable;
    defer CFRelease(position);
    const size = attribute(window, "AXSize") orelse return error.WindowUnavailable;
    defer CFRelease(size);
    if (CFGetTypeID(position) != AXValueGetTypeID() or CFGetTypeID(size) != AXValueGetTypeID()) return error.WindowUnavailable;
    var point: objc.CGPoint = undefined;
    var dimensions: objc.CGSize = undefined;
    if (AXValueGetValue(position, 1, &point) == 0 or AXValueGetValue(size, 2, &dimensions) == 0) return error.WindowUnavailable;
    const bounds: layout.Rect = .{ .x = point.x, .y = point.y, .w = dimensions.width, .h = dimensions.height };
    if (!bounds.valid()) return error.WindowUnavailable;
    return bounds;
}

fn settable(window: Ref, name: []const u8) bool {
    var yes: u8 = 0;
    return AXUIElementIsAttributeSettable(window, objc.nsString(name), &yes) == 0 and yes != 0;
}

fn apply(window: Ref, before: layout.Rect, destination: layout.Rect) layout.Failure!void {
    const resize = @abs(before.w - destination.w) > 0.5 or @abs(before.h - destination.h) > 0.5;
    if (!settable(window, "AXPosition")) return error.CannotMove;
    if (resize and !settable(window, "AXSize")) return error.CannotResize;
    const point: objc.CGPoint = .{ .x = destination.x, .y = destination.y };
    const dimensions: objc.CGSize = .{ .width = destination.w, .height = destination.h };
    const position = AXValueCreate(1, &point) orelse return error.WindowUnavailable;
    defer CFRelease(position);
    const size = AXValueCreate(2, &dimensions) orelse return error.WindowUnavailable;
    defer CFRelease(size);
    if (resize and AXUIElementSetAttributeValue(window, objc.nsString("AXSize"), size) != 0) return error.CannotResize;
    if (AXUIElementSetAttributeValue(window, objc.nsString("AXPosition"), position) != 0) return error.CannotMove;
    if (resize) {
        if (AXUIElementSetAttributeValue(window, objc.nsString("AXSize"), size) != 0) return error.CannotResize;
        if (AXUIElementSetAttributeValue(window, objc.nsString("AXPosition"), position) != 0) return error.CannotMove;
    }
}

fn rect(frame_in: objc.CGRect, primary_top: f64) layout.Rect {
    return layout.fromAppKit(.{ .x = frame_in.origin.x, .y = frame_in.origin.y, .w = frame_in.size.width, .h = frame_in.size.height }, primary_top);
}

fn screens(buf: []layout.Display) []layout.Display {
    const list = objc.msg(objc.Object, objc.class("NSScreen"), "screens", .{});
    const count = objc.msg(objc.NSUInteger, list, "count", .{});
    if (count == 0) return buf[0..0];
    const first = objc.msg(objc.Object, list, "objectAtIndex:", .{@as(objc.NSUInteger, 0)});
    const primary = objc.msg(objc.CGRect, first, "frame", .{});
    const top = primary.origin.y + primary.size.height;
    const n = @min(count, buf.len);
    for (buf[0..n], 0..) |*display, i| {
        const screen = objc.msg(objc.Object, list, "objectAtIndex:", .{i});
        display.* = .{ .bounds = rect(objc.msg(objc.CGRect, screen, "frame", .{}), top), .usable = rect(objc.msg(objc.CGRect, screen, "visibleFrame", .{}), top) };
    }
    std.sort.pdq(layout.Display, buf[0..n], {}, struct {
        fn before(_: void, a: layout.Display, b: layout.Display) bool {
            return if (a.bounds.x != b.bounds.x) a.bounds.x < b.bounds.x else a.bounds.y < b.bounds.y;
        }
    }.before);
    return buf[0..n];
}

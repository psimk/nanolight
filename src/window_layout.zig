const std = @import("std");
const search = @import("search.zig");

pub const Action = enum {
    left_half,
    right_half,
    top_half,
    bottom_half,
    top_left_quarter,
    top_right_quarter,
    bottom_left_quarter,
    bottom_right_quarter,
    maximize,
    center,
    restore,
    previous_display,
    next_display,

    pub const all = std.enums.values(Action);
    pub const names = [_][]const u8{
        "Left Half",        "Right Half",        "Top Half",            "Bottom Half",
        "Top Left Quarter", "Top Right Quarter", "Bottom Left Quarter", "Bottom Right Quarter",
        "Maximize",         "Center",            "Restore",             "Previous Display",
        "Next Display",
    };

    pub fn label(action: Action) []const u8 {
        return names[@backingInt(action)];
    }
};

pub const Failure = error{
    AccessibilityRequired,
    NoWindow,
    FullscreenWindow,
    CannotMove,
    CannotResize,
    WindowUnavailable,
    NothingToRestore,
    OnlyOneDisplay,
    NoDisplay,
    CommandUnavailable,
};

pub fn message(failure: Failure) []const u8 {
    return switch (failure) {
        error.AccessibilityRequired => "Allow Nanolight in Privacy & Security → Accessibility, then retry this command.",
        error.NoWindow => "Focus an app window, then open Nanolight and retry this command.",
        error.FullscreenWindow => "Leave full screen before arranging this window.",
        error.CannotMove => "This app does not allow this window to move.",
        error.CannotResize => "This app does not allow this window to resize.",
        error.WindowUnavailable => "The window is unavailable or did not accept the change. Try again.",
        error.NothingToRestore => "This window has no saved position to restore.",
        error.OnlyOneDisplay => "Connect another display to move this window between displays.",
        error.NoDisplay => "No display is available for this window.",
        error.CommandUnavailable => "Window commands are unavailable in this view.",
    };
}

pub const Rect = struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,

    pub fn valid(r: Rect) bool {
        return std.math.isFinite(r.x) and std.math.isFinite(r.y) and std.math.isFinite(r.w) and std.math.isFinite(r.h) and r.w > 0 and r.h > 0;
    }

    fn part(r: Rect, x: f64, y: f64, w: f64, h: f64) Rect {
        const left = @floor(r.w * x);
        const top = @floor(r.h * y);
        return .{ .x = r.x + left, .y = r.y + top, .w = @floor(r.w * (x + w)) - left, .h = @floor(r.h * (y + h)) - top };
    }

    fn fit(r: Rect, bounds: Rect) Rect {
        const w = @min(r.w, bounds.w);
        const h = @min(r.h, bounds.h);
        return .{ .x = std.math.clamp(r.x, bounds.x, bounds.x + bounds.w - w), .y = std.math.clamp(r.y, bounds.y, bounds.y + bounds.h - h), .w = w, .h = h };
    }
};

pub const Display = struct { bounds: Rect, usable: Rect };

pub fn fromAppKit(frame: Rect, primary_top: f64) Rect {
    return .{ .x = frame.x, .y = primary_top - frame.y - frame.h, .w = frame.w, .h = frame.h };
}

pub fn displayFor(frame: Rect, displays: []const Display) ?usize {
    var best: ?usize = null;
    var best_area: f64 = -1;
    var best_distance: f64 = std.math.inf(f64);
    for (displays, 0..) |display, i| {
        const b = display.bounds;
        if (!b.valid() or !display.usable.valid()) continue;
        const w = @max(0, @min(frame.x + frame.w, b.x + b.w) - @max(frame.x, b.x));
        const h = @max(0, @min(frame.y + frame.h, b.y + b.h) - @max(frame.y, b.y));
        const area = w * h;
        const cx = frame.x + frame.w / 2;
        const cy = frame.y + frame.h / 2;
        const dx = cx - std.math.clamp(cx, b.x, b.x + b.w);
        const dy = cy - std.math.clamp(cy, b.y, b.y + b.h);
        const distance = dx * dx + dy * dy;
        if (area > best_area or (area == best_area and distance < best_distance)) {
            best = i;
            best_area = area;
            best_distance = distance;
        }
    }
    return best;
}

pub fn target(action: Action, frame: Rect, displays: []const Display, saved: ?Rect) Failure!Rect {
    if (!frame.valid()) return error.WindowUnavailable;
    const current = displayFor(frame, displays) orelse return error.NoDisplay;
    const bounds = displays[current].usable;
    return switch (action) {
        .left_half => bounds.part(0, 0, 0.5, 1),
        .right_half => bounds.part(0.5, 0, 0.5, 1),
        .top_half => bounds.part(0, 0, 1, 0.5),
        .bottom_half => bounds.part(0, 0.5, 1, 0.5),
        .top_left_quarter => bounds.part(0, 0, 0.5, 0.5),
        .top_right_quarter => bounds.part(0.5, 0, 0.5, 0.5),
        .bottom_left_quarter => bounds.part(0, 0.5, 0.5, 0.5),
        .bottom_right_quarter => bounds.part(0.5, 0.5, 0.5, 0.5),
        .maximize => bounds,
        .center => .{ .x = bounds.x + (bounds.w - frame.w) / 2, .y = bounds.y + (bounds.h - frame.h) / 2, .w = frame.w, .h = frame.h },
        .restore => blk: {
            const original = saved orelse return error.NothingToRestore;
            if (!original.valid()) return error.NothingToRestore;
            const screen = displayFor(original, displays) orelse return error.NoDisplay;
            break :blk original.fit(displays[screen].usable);
        },
        .previous_display, .next_display => blk: {
            if (displays.len < 2) return error.OnlyOneDisplay;
            const next = if (action == .next_display) (current + 1) % displays.len else (current + displays.len - 1) % displays.len;
            const to = displays[next].usable;
            if (!to.valid()) return error.NoDisplay;
            break :blk (Rect{
                .x = to.x + (frame.x - bounds.x) / bounds.w * to.w,
                .y = to.y + (frame.y - bounds.y) / bounds.h * to.h,
                .w = frame.w / bounds.w * to.w,
                .h = frame.h / bounds.h * to.h,
            }).fit(to);
        },
    };
}

pub fn rank(query_in: []const u8, out: []search.Ranked) usize {
    var query = std.mem.trim(u8, query_in, " ");
    if (std.ascii.eqlIgnoreCase(query, "window") or std.ascii.eqlIgnoreCase(query, "windows")) {
        const n = @min(out.len, Action.all.len);
        for (out[0..n], 0..) |*entry, i| entry.* = .{ .index = @intCast(i), .match = .{ .score = 1000 } };
        return n;
    }
    if (std.ascii.startsWithIgnoreCase(query, "window ")) query = std.mem.trim(u8, query[7..], " ");
    if (std.ascii.endsWithIgnoreCase(query, " window")) query = std.mem.trim(u8, query[0 .. query.len - 7], " ");
    if (query.len < 2) return 0;
    const n = search.rank(query, &Action.names, &.{}, out);
    var kept: usize = 0;
    for (out[0..n]) |entry| {
        if (entry.match.score < 600) continue;
        out[kept] = entry;
        kept += 1;
    }
    return kept;
}

test "halves and quarters meet without gaps on an odd-sized usable display" {
    const display: Display = .{ .bounds = .{ .x = -1441, .y = -900, .w = 1441, .h = 900 }, .usable = .{ .x = -1441, .y = -875, .w = 1441, .h = 851 } };
    const current: Rect = .{ .x = -1300, .y = -800, .w = 600, .h = 400 };
    const expected = [_]Rect{
        .{ .x = -1441, .y = -875, .w = 720, .h = 851 },
        .{ .x = -721, .y = -875, .w = 721, .h = 851 },
        .{ .x = -1441, .y = -875, .w = 1441, .h = 425 },
        .{ .x = -1441, .y = -450, .w = 1441, .h = 426 },
        .{ .x = -1441, .y = -875, .w = 720, .h = 425 },
        .{ .x = -721, .y = -875, .w = 721, .h = 425 },
        .{ .x = -1441, .y = -450, .w = 720, .h = 426 },
        .{ .x = -721, .y = -450, .w = 721, .h = 426 },
    };
    for (Action.all[0..8], expected) |action, rect| try std.testing.expectEqualDeep(rect, try target(action, current, &.{display}, null));
    try std.testing.expectEqualDeep(display.usable, try target(.maximize, current, &.{display}, null));
    const centered = try target(.center, current, &.{display}, null);
    try std.testing.expectEqual(current.w, centered.w);
    try std.testing.expectEqual(current.h, centered.h);
    try std.testing.expectEqual(display.usable.x + display.usable.w / 2, centered.x + centered.w / 2);
    try std.testing.expectEqual(display.usable.y + display.usable.h / 2, centered.y + centered.h / 2);
}

test "AppKit frames convert to accessibility coordinates across displays" {
    try std.testing.expectEqualDeep(Rect{ .x = -1440, .y = -180, .w = 1440, .h = 1080 }, fromAppKit(.{ .x = -1440, .y = 0, .w = 1440, .h = 1080 }, 900));
    try std.testing.expectEqualDeep(Rect{ .x = 0, .y = -1080, .w = 1920, .h = 1080 }, fromAppKit(.{ .x = 0, .y = 900, .w = 1920, .h = 1080 }, 900));
}

test "display moves preserve layout proportions, wrap, and reject one display" {
    const displays = [_]Display{
        .{ .bounds = .{ .x = -1200, .y = 0, .w = 1200, .h = 800 }, .usable = .{ .x = -1200, .y = 24, .w = 1200, .h = 720 } },
        .{ .bounds = .{ .x = 0, .y = 0, .w = 1600, .h = 1000 }, .usable = .{ .x = 0, .y = 24, .w = 1600, .h = 900 } },
    };
    const left: Rect = .{ .x = -600, .y = 24, .w = 600, .h = 720 };
    const right: Rect = .{ .x = 800, .y = 24, .w = 800, .h = 900 };
    try std.testing.expectEqualDeep(right, try target(.next_display, left, &displays, null));
    try std.testing.expectEqualDeep(left, try target(.previous_display, right, &displays, null));
    try std.testing.expectEqualDeep(left, try target(.next_display, right, &displays, null));
    try std.testing.expectError(error.OnlyOneDisplay, target(.next_display, right, displays[1..], null));
    try std.testing.expectError(error.NoDisplay, target(.maximize, right, &.{}, null));
    try std.testing.expectEqual(@as(usize, 1), displayFor(.{ .x = -100, .y = 100, .w = 800, .h = 400 }, &displays).?);
}

test "restore keeps the saved frame visible after a display is removed" {
    const display: Display = .{ .bounds = .{ .x = 0, .y = 0, .w = 1200, .h = 800 }, .usable = .{ .x = 0, .y = 24, .w = 1200, .h = 720 } };
    const original: Rect = .{ .x = 80, .y = 50, .w = 640, .h = 480 };
    try std.testing.expectEqualDeep(original, try target(.restore, display.usable, &.{display}, original));
    try std.testing.expectError(error.NothingToRestore, target(.restore, display.usable, &.{display}, null));
    const offscreen: Rect = .{ .x = -2000, .y = -900, .w = 1800, .h = 1000 };
    try std.testing.expectEqualDeep(display.usable, try target(.restore, display.usable, &.{display}, offscreen));
}

test "commands match names and a window prefix without matching ordinary searches" {
    var out: [6]search.Ranked = undefined;
    for ([_][]const u8{ "left half", "window left half", "Left Half Window" }) |query| {
        try std.testing.expect(rank(query, &out) > 0);
        try std.testing.expectEqual(Action.left_half, Action.all[out[0].index]);
    }
    try std.testing.expectEqual(@as(usize, 6), rank("window", &out));
    try std.testing.expectEqual(@as(usize, 4), rank("quarter", &out));
    for ([_][]const u8{ "saf", "liquid glass", "pizza", "a", "" }) |query| try std.testing.expectEqual(@as(usize, 0), rank(query, &out));
}

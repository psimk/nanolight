//! Nanolight's parts, and its panel driven through a Tester: keys in,
//! rows and the clipboard out. Nothing is opened; no window shows.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const Index = @import("apps.zig").Index;
const view = @import("view.zig");
const window_layout = @import("window_layout.zig");

test {
    _ = @import("search.zig");
    _ = @import("calc.zig");
    _ = @import("results.zig");
    _ = @import("suggest.zig");
    _ = @import("promo_camera.zig");
    _ = @import("single.zig");
    _ = @import("clickthrough.zig");
    _ = @import("settings.zig");
    _ = @import("apps.zig");
    _ = @import("hotkey.zig");
    _ = @import("shortcut.zig");
}

const Probe = struct {
    opened: [256]u8 = undefined,
    opened_len: usize = 0,
    hidden: bool = false,

    fn open(ctx: *anyopaque, target: []const u8) void {
        const p: *Probe = @ptrCast(@alignCast(ctx));
        @memcpy(p.opened[0..target.len], target);
        p.opened_len = target.len;
    }
    fn hide(ctx: *anyopaque) void {
        const p: *Probe = @ptrCast(@alignCast(ctx));
        p.hidden = true;
    }
};

fn press(t: *ui.Tester, ops: []const ui.TextOp) void {
    t.textOps(ops);
    t.settle(1);
}

test "the panel finds, moves, answers and hands off" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    for ([_][]const u8{ "Safari", "System Settings", "Notes", "Calculator", "Finder" }) |n| {
        var buf: [64]u8 = undefined;
        try ix.add(n, try std.fmt.bufPrint(&buf, "/Applications/{s}.app", .{n}));
    }
    var probe: Probe = .{};
    var s: view.Nanolight = .{ .index = &ix };
    defer s.query.deinit();
    s.host = .{ .ctx = &probe, .open = Probe.open, .hide = Probe.hide };
    s.reveal();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = 480, .dark = true });
    defer t.deinit();
    t.settle(1);
    // No query: suggestions.
    try std.testing.expect(t.hasText("Suggestions"));
    try std.testing.expect(t.hasText("Safari"));
    // After an automatic update, the footer says so in place of the name.
    try std.testing.expect(t.hasText("Nanolight · 5 apps"));
    s.note = "Updated to 0.1.3";
    t.settle(1);
    try std.testing.expect(t.hasText("Updated to 0.1.3 · 5 apps"));
    s.note = "";

    // The top app's name completes what is typed; → takes it.
    press(&t, &.{.{ .insert = "saf" }});
    try std.testing.expect(t.hasText("ari"));
    press(&t, &.{.{ .command = .move_right }});
    try std.testing.expectEqualStrings("safari", s.query.text());
    press(&t, &.{ .{ .command = .select_all }, .{ .command = .delete_backward } });

    press(&t, &.{.{ .insert = "ss" }});
    try std.testing.expect(t.hasText("System Settings"));
    try std.testing.expectEqual(@as(u32, ix.find("System Settings").?), s.res.rows[0].app);
    // Down and back up, then Return opens the first.
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.down }));
    try std.testing.expectEqual(@as(usize, 1), s.sel);
    _ = t.shortcut(.{ .key = ui.Shortcut.up });
    press(&t, &.{.{ .command = .insert_newline }});
    try std.testing.expectEqualStrings("/Applications/System Settings.app", probe.opened[0..probe.opened_len]);
    try std.testing.expect(probe.hidden);
    try std.testing.expectEqual(@as(u16, 1), ix.launches.items[ix.find("System Settings").?]);

    // ⌘2 opens the second row at once: Safari, under System Settings,
    // which was just opened.
    press(&t, &.{ .{ .command = .select_all }, .{ .command = .delete_backward }, .{ .insert = "s" } });
    try std.testing.expect(t.hasText("⌘2"));
    try std.testing.expect(t.shortcut(.{ .key = '2', .cmd = true }));
    try std.testing.expectEqualStrings("/Applications/Safari.app", probe.opened[0..probe.opened_len]);

    // Math: answered, and Return copies it.
    press(&t, &.{ .{ .command = .select_all }, .{ .command = .delete_backward }, .{ .insert = "2^10 * 3" } });
    try std.testing.expect(t.hasText("3,072"));
    try std.testing.expect(t.hasText("Result · 0xC00"));
    press(&t, &.{.{ .command = .insert_newline }});
    try std.testing.expectEqualStrings("3072", t.clipboard.items);

    // Anything else: DuckDuckGo and Grok.
    press(&t, &.{ .{ .command = .select_all }, .{ .command = .delete_backward }, .{ .insert = "liquid glass" } });
    try std.testing.expect(t.containsText("Search DuckDuckGo for"));
    try std.testing.expect(!t.containsText("Search X"));
    try std.testing.expect(!t.containsText("Google"));
    _ = t.shortcut(.{ .key = ui.Shortcut.down });
    press(&t, &.{.{ .command = .insert_newline }});
    try std.testing.expectEqualStrings("https://grok.com/?q=liquid+glass", probe.opened[0..probe.opened_len]);

    // Escape clears the query, then closes.
    probe.hidden = false;
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    try std.testing.expectEqualStrings("", s.query.text());
    try std.testing.expect(!probe.hidden);
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    try std.testing.expect(probe.hidden);
}

const suggest = @import("suggest.zig");
const results = @import("results.zig");

/// A host that answers for DuckDuckGo and opens searches in the browser.
const Web = struct {
    probe: Probe = .{},
    asked: [64]u8 = undefined,
    asked_len: usize = 0,

    fn host(w: *Web) view.Host {
        return .{ .ctx = w, .open = open, .hide = hide, .suggest = ask };
    }
    fn open(ctx: *anyopaque, target: []const u8) void {
        const w: *Web = @ptrCast(@alignCast(ctx));
        Probe.open(&w.probe, target);
    }
    fn hide(ctx: *anyopaque) void {
        const w: *Web = @ptrCast(@alignCast(ctx));
        Probe.hide(&w.probe);
    }
    fn ask(ctx: *anyopaque, q: []const u8) void {
        const w: *Web = @ptrCast(@alignCast(ctx));
        @memcpy(w.asked[0..q.len], q);
        w.asked_len = q.len;
    }
};

test "DuckDuckGo's completions land below, and searches open in the browser" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    try ix.add("Safari", "/Applications/Safari.app");
    var web: Web = .{};
    var s: view.Nanolight = .{ .index = &ix };
    defer s.query.deinit();
    s.host = web.host();
    s.reveal();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = view.max_height, .dark = true });
    defer t.deinit();
    t.settle(1);
    // An address is never asked about; words are.
    press(&t, &.{.{ .insert = "ziglang.org" }});
    try std.testing.expectEqual(@as(usize, 0), web.asked_len);
    press(&t, &.{ .{ .command = .select_all }, .{ .command = .delete_backward }, .{ .insert = "liquid gl" } });
    try std.testing.expectEqualStrings("liquid gl", web.asked[0..web.asked_len]);
    // Return would search what was typed. The selection, moved before
    // the answer comes, stays on its row, though the completions land
    // above it, a key under the search.
    try std.testing.expectEqual(results.Kind.search_web, s.res.rows[s.sel].kind);
    _ = t.shortcut(.{ .key = ui.Shortcut.down });
    try std.testing.expectEqual(results.Kind.ask_grok, s.res.rows[s.sel].kind);
    var said: suggest.List = .{};
    for ([_][]const u8{ "liquid glass", "liquid glass apple" }) |w| said.push(w);
    s.answered("liquid gl", &said);
    t.settle(1);
    try std.testing.expect(t.hasText("DuckDuckGo"));
    try std.testing.expect(t.hasText("liquid glass apple"));
    try std.testing.expectEqual(results.Kind.suggest, s.res.rows[1].kind);
    try std.testing.expectEqual(results.Kind.ask_grok, s.res.rows[s.sel].kind);
    // The first completion shows faintly in the field; Tab takes it.
    try std.testing.expect(t.hasText("ass"));
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.tab }));
    t.settle(1);
    try std.testing.expectEqualStrings("liquid glass", s.query.text());
    press(&t, &.{ .{ .command = .select_all }, .{ .command = .delete_backward }, .{ .insert = "liquid gl" } });
    // Known at once this time, yet Return still searches what was typed,
    // not a completion nobody picked.
    try std.testing.expectEqual(results.Kind.suggest, s.res.rows[1].kind);
    try std.testing.expectEqual(results.Kind.search_web, s.res.rows[s.sel].kind);
    // ⌘2 is DuckDuckGo's first completion.
    try std.testing.expect(t.hasText("⌘2"));
    // One more letter: the answer so far stands in, and nothing is asked
    // again for words already answered.
    web.asked_len = 0;
    press(&t, &.{.{ .insert = "a" }});
    try std.testing.expectEqualStrings("liquid gla", web.asked[0..web.asked_len]);
    try std.testing.expect(t.hasText("liquid glass apple"));
    web.asked_len = 0;
    press(&t, &.{.{ .command = .delete_backward }});
    try std.testing.expectEqual(@as(usize, 0), web.asked_len);

    // ⌘3 opens the second completion in the browser and hides the panel.
    try std.testing.expect(t.shortcut(.{ .key = '3', .cmd = true }));
    t.settle(1);
    try std.testing.expectEqualStrings("liquid glass apple", s.query.text());
    try std.testing.expectEqualStrings("https://duckduckgo.com/?q=liquid+glass+apple", web.probe.opened[0..web.probe.opened_len]);
    try std.testing.expect(web.probe.hidden);
    try std.testing.expect(!s.previewing);
    try std.testing.expect(!t.hasText("Open in Browser"));

    s.reveal();
    web.probe = .{};
    press(&t, &.{ .{ .command = .select_all }, .{ .command = .delete_backward }, .{ .insert = "pizza" } });
    try std.testing.expect(!web.probe.hidden);
    press(&t, &.{.{ .command = .insert_newline }});
    try std.testing.expectEqualStrings("https://duckduckgo.com/?q=pizza", web.probe.opened[0..web.probe.opened_len]);
    try std.testing.expect(web.probe.hidden);
    try std.testing.expect(!s.previewing);
    try std.testing.expectEqualStrings("pizza", s.query.text());

    s.reveal();
    web.probe = .{};
    t.settle(1);
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.enter, .cmd = true }));
    try std.testing.expectEqualStrings("https://duckduckgo.com/?q=pizza", web.probe.opened[0..web.probe.opened_len]);
    try std.testing.expect(web.probe.hidden);
    try std.testing.expect(!s.previewing);
}

const onboard = @import("onboard.zig");
const shortcut = @import("shortcut.zig");

const Steps = struct {
    applied: ?shortcut.Choice = null,
    done: bool = false,
    fn apply(ctx: *anyopaque, c: shortcut.Choice) void {
        const p: *Steps = @ptrCast(@alignCast(ctx));
        p.applied = c;
    }
    fn fix(_: *anyopaque, _: shortcut.Clash) void {}
    fn finished(ctx: *anyopaque) void {
        const p: *Steps = @ptrCast(@alignCast(ctx));
        p.done = true;
    }
};

test "the welcome: a key, pressed for real, then a first search" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    try ix.add("Safari", "/Applications/Safari.app");
    var o: onboard.Onboard = .{};
    // Hooks only once started: the system's shortcuts are not read in tests.
    o.start(.cmd_space);
    const sys = [_]shortcut.SystemKey{.{ .id = 64, .enabled = true, .key = 49, .mods = 1 << 20 }};
    o.system = &sys;
    var steps: Steps = .{};
    o.hooks = .{ .ctx = &steps, .apply = Steps.apply, .fix = Steps.fix, .done = Steps.finished };
    var s: view.Nanolight = .{ .index = &ix, .onboard = &o };
    defer s.query.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = 480, .dark = true });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.hasText("Welcome to Nanolight"));
    // Who holds ⌘Space, by name; going on anyway is said as such.
    try std.testing.expect(t.hasText("macOS gives ⌘ Space to Spotlight first."));
    try std.testing.expect(t.hasText("Use ⌘ Space anyway"));
    t.key(.right);
    try std.testing.expect(t.hasText("⌥ Space is free on this Mac."));
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(shortcut.Choice.opt_space, steps.applied.?);
    try std.testing.expect(t.hasText("Press ⌥ Space now"));
    // A button never moves it on: the key closing the panel, then opening it.
    o.pressed(false);
    t.settle(1);
    try std.testing.expectEqual(onboard.Step.try_it, o.step);
    o.pressed(true);
    o.pressed(false);
    t.settle(2);
    try std.testing.expect(t.hasText("You're set."));
    // ⌘2: the math example, run in the launcher.
    try std.testing.expect(t.shortcut(.{ .key = '2', .cmd = true }));
    t.settle(1);
    try std.testing.expect(steps.done and !o.active);
    try std.testing.expect(t.hasText("3,072"));

    // Esc skips from the first step, keeping the key shown there.
    steps = .{};
    o.start(.ctrl_space);
    t.settle(1);
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    try std.testing.expect(steps.done and !o.active);
    try std.testing.expectEqual(shortcut.Choice.ctrl_space, steps.applied.?);
}

test "Command D can be picked and tried in the welcome" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    var o: onboard.Onboard = .{};
    o.start(.cmd_space);
    var steps: Steps = .{};
    o.hooks = .{ .ctx = &steps, .apply = Steps.apply, .fix = Steps.fix, .done = Steps.finished };
    var s: view.Nanolight = .{ .index = &ix, .onboard = &o };
    defer s.query.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = 480, .dark = true });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.hasText("⌘ D"));
    t.key(.left);
    try std.testing.expectEqual(shortcut.Choice.cmd_d, o.choice);
    try std.testing.expect(t.hasText("⌘ D is free on this Mac."));
    t.key(.right);
    try std.testing.expectEqual(shortcut.Choice.cmd_space, o.choice);
    t.key(.left);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(shortcut.Choice.cmd_d, steps.applied.?);
    try std.testing.expect(t.hasText("Press ⌘ D now"));
    try std.testing.expect(t.hasText("D"));
    try std.testing.expect(!t.hasText("Space"));
    o.pressed(true);
    o.pressed(false);
    t.settle(2);
    try std.testing.expectEqual(onboard.Step.done, o.step);
    try std.testing.expect(t.hasText("⌘ D opens it anywhere. Start with one of these:"));
}

test "the panel never outgrows its window, which is never resized" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    for ([_][]const u8{ "Safari", "Mail", "Maps", "Music", "Notes", "Numbers", "Pages", "Photos", "Calendar", "Calculator" }) |n| {
        var buf: [64]u8 = undefined;
        try ix.add(n, try std.fmt.bufPrint(&buf, "/Applications/{s}.app", .{n}));
    }
    var s: view.Nanolight = .{ .index = &ix };
    defer s.query.deinit();
    var tallest: f32 = 0;
    for ([_][]const u8{ "", "a", "s", "ma", "2^10 * 3", "1+a", "liquid glass" }) |q| {
        s.query.set(q);
        s.rebuild();
        tallest = @max(tallest, s.height());
    }
    try std.testing.expect(tallest <= view.max_height);
    // "a" fills every app row there is, and DuckDuckGo's completions the
    // rest: the bound is the real one.
    s.query.set("a");
    s.rebuild();
    var four: @import("suggest.zig").List = .{};
    for ([_][]const u8{ "a1", "a2", "a3", "a4" }) |w| four.push(w);
    s.answered("a", &four);
    try std.testing.expectEqual(view.max_height, s.height());
    var o: onboard.Onboard = .{};
    for ([_]onboard.Step{ .key, .try_it, .done }) |step| {
        o.step = step;
        try std.testing.expect(o.height() <= view.max_height);
    }
}

const WindowProbe = struct {
    action: ?window_layout.Action = null,
    failure: ?window_layout.Failure = null,
    hidden: bool = false,
    opened: bool = false,
    asked: bool = false,
    settings_opened: bool = false,

    fn host(probe: *WindowProbe) view.Host {
        return .{ .ctx = probe, .open = open, .hide = hide, .suggest = ask, .arrange = arrange, .accessibility = settings };
    }

    fn open(ctx: *anyopaque, _: []const u8) void {
        const probe: *WindowProbe = @ptrCast(@alignCast(ctx));
        probe.opened = true;
    }

    fn hide(ctx: *anyopaque) void {
        const probe: *WindowProbe = @ptrCast(@alignCast(ctx));
        probe.hidden = true;
    }

    fn ask(ctx: *anyopaque, _: []const u8) void {
        const probe: *WindowProbe = @ptrCast(@alignCast(ctx));
        probe.asked = true;
    }

    fn arrange(ctx: *anyopaque, action: window_layout.Action) window_layout.Failure!void {
        const probe: *WindowProbe = @ptrCast(@alignCast(ctx));
        probe.action = action;
        if (probe.failure) |failure| return failure;
    }

    fn settings(ctx: *anyopaque) void {
        const probe: *WindowProbe = @ptrCast(@alignCast(ctx));
        probe.settings_opened = true;
    }
};

test "window commands run from the launcher without opening apps or sending queries" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    var probe: WindowProbe = .{};
    var s: view.Nanolight = .{ .index = &ix, .host = probe.host() };
    defer s.query.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = view.max_height, .dark = true });
    defer t.deinit();
    for (window_layout.Action.all) |action| {
        probe = .{};
        s.reveal();
        press(&t, &.{ .{ .command = .select_all }, .{ .command = .delete_backward }, .{ .insert = action.label() } });
        try std.testing.expect(t.hasText("Window Management"));
        try std.testing.expect(t.hasText(action.label()));
        try std.testing.expectEqual(results.Kind.window, s.res.rows[0].kind);
        try std.testing.expectEqual(action, s.res.rows[0].window);
        try std.testing.expect(s.height() <= view.max_height);
        press(&t, &.{.{ .command = .insert_newline }});
        try std.testing.expectEqual(action, probe.action.?);
        try std.testing.expect(probe.hidden);
        try std.testing.expect(!probe.opened and !probe.asked);
    }
    probe = .{};
    s.reveal();
    press(&t, &.{ .{ .command = .select_all }, .{ .command = .delete_backward }, .{ .insert = "window" } });
    try std.testing.expect(t.shortcut(.{ .key = '2', .cmd = true }));
    try std.testing.expectEqual(window_layout.Action.right_half, probe.action.?);
    try std.testing.expect(probe.hidden and !probe.opened and !probe.asked);
}

test "window failures explain how to retry and keep the launcher open" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    for (0..6) |i| {
        var name: [32]u8 = undefined;
        var path: [64]u8 = undefined;
        try ix.add(try std.fmt.bufPrint(&name, "Left Helper {d}", .{i}), try std.fmt.bufPrint(&path, "/Applications/Left Helper {d}.app", .{i}));
    }
    var probe: WindowProbe = .{ .failure = error.AccessibilityRequired };
    var s: view.Nanolight = .{ .index = &ix, .host = probe.host() };
    defer s.query.deinit();
    s.reveal();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = view.max_height, .dark = true });
    defer t.deinit();
    press(&t, &.{.{ .insert = "left" }});
    press(&t, &.{.{ .command = .insert_newline }});
    try std.testing.expect(t.hasText(window_layout.message(error.AccessibilityRequired)));
    try std.testing.expect(t.hasText("Open Settings"));
    try t.clickText("Open Settings");
    try std.testing.expect(probe.settings_opened);
    s.query.focus();
    t.settle(1);
    try std.testing.expect(!probe.hidden and !probe.opened and !probe.asked);
    try std.testing.expect(s.height() <= view.max_height);
    for ([_]window_layout.Failure{ error.NoWindow, error.CannotResize, error.FullscreenWindow, error.NothingToRestore, error.OnlyOneDisplay }) |failure| {
        probe.failure = failure;
        press(&t, &.{.{ .command = .insert_newline }});
        try std.testing.expectEqual(failure, s.failure.?);
        try std.testing.expect(t.hasText(window_layout.message(failure)));
        try std.testing.expect(!t.hasText("Open Settings"));
        try std.testing.expect(!probe.hidden and !probe.opened);
    }
    probe.failure = null;
    press(&t, &.{.{ .command = .insert_newline }});
    try std.testing.expect(probe.hidden);
    try std.testing.expect(s.failure == null);
    try std.testing.expectEqual(window_layout.Action.left_half, probe.action.?);
}

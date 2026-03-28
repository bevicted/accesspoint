# TUI Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace v1 parser/Entries with v2 parser/Layers, update the TUI to navigate layers and return a selected leaf, and add instruction execution in main.zig.

**Architecture:** The TUI is focused on display and navigation only — it accepts Layers, shows sublayers for navigation, and returns the selected leaf layer index (?usize). main.zig handles CLI args, file reading, parsing, and instruction execution. On leaf selection, main.zig walks the parent chain from leaf to root, collects all instructions in root→leaf order, and executes them sequentially.

**Tech Stack:** Zig, vaxis (TUI framework), v2 parser (already implemented)

---

## File Structure

| File | Responsibility |
|---|---|
| `src/main.zig` | CLI args, file reading, v2 parser call, instruction execution |
| `src/tui.zig` | Layer navigation TUI, returns selected leaf index |
| `src/parser.zig` | **DELETE** — v1 parser |
| `src/entries.zig` | **DELETE** — v1 data model |
| `test.ap` | **DELETE** — v1 format file |

---

### Task 1: Rewrite tui.zig

**Files:**
- Modify: `src/tui.zig`

- [ ] **Step 1: Rewrite tui.zig**

Replace the entire file with:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const TextSpan = vxfw.RichText.TextSpan;

const models = @import("parser/models.zig");

const DisplayItem = struct {
    rich_text: vxfw.RichText,
    idx: usize,
};

const Model = struct {
    arena: std.heap.ArenaAllocator,
    filtered: std.ArrayList(DisplayItem),
    list_view: vxfw.ListView,
    text_field: vxfw.TextField,
    layers: models.Layers,
    current_layer: usize,
    selected_layer: ?usize,

    pub fn init(allocator: Allocator, layers: models.Layers) !*Model {
        const model = try allocator.create(Model);
        model.* = .{
            .filtered = .empty,
            .list_view = .{
                .children = .{
                    .builder = .{
                        .userdata = model,
                        .buildFn = Model.widgetBuilder,
                    },
                },
            },
            .text_field = .{
                .buf = vxfw.TextField.Buffer.init(allocator),
                .userdata = model,
                .onChange = Model.onChange,
                .onSubmit = Model.onSubmit,
            },
            .layers = layers,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .current_layer = 0,
            .selected_layer = null,
        };

        return model;
    }

    pub fn deinit(self: *Model, allocator: Allocator) void {
        self.text_field.deinit();
        self.arena.deinit();
        allocator.destroy(self);
    }

    pub fn widget(self: *Model) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Model.typeErasedEventHandler,
            .drawFn = Model.typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *Model = @ptrCast(@alignCast(ptr));
        switch (event) {
            .init => {
                try self.repopulate_list("");
                return ctx.requestFocus(self.text_field.widget());
            },
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }

                if (key.matches(vaxis.Key.escape, .{})) {
                    if (self.layers.items[self.current_layer].parent) |p| {
                        self.current_layer = p;
                        try self.repopulate_list("");
                    }
                }

                return self.list_view.handleEvent(ctx, event);
            },
            .focus_in => {
                return ctx.requestFocus(self.text_field.widget());
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));
        const max = ctx.max.size();

        const list_view: vxfw.SubSurface = .{
            .origin = .{ .row = 2, .col = 0 },
            .surface = try self.list_view.draw(ctx.withConstraints(
                ctx.min,
                .{ .width = max.width, .height = max.height - 3 },
            )),
        };

        const text_field: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 2 },
            .surface = try self.text_field.draw(ctx.withConstraints(
                ctx.min,
                .{ .width = max.width, .height = 1 },
            )),
        };

        const prompt: vxfw.Text = .{ .text = "", .style = .{ .fg = .{ .index = 4 } } };

        const prompt_surface: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try prompt.draw(ctx.withConstraints(ctx.min, .{ .width = 2, .height = 1 })),
        };

        const children = try ctx.arena.alloc(vxfw.SubSurface, 3);
        children[0] = list_view;
        children[1] = text_field;
        children[2] = prompt_surface;

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }

    fn widgetBuilder(ptr: *const anyopaque, idx: usize, _: usize) ?vxfw.Widget {
        const self: *const Model = @ptrCast(@alignCast(ptr));
        if (idx >= self.filtered.items.len) return null;

        return self.filtered.items[idx].rich_text.widget();
    }

    fn onChange(maybe_ptr: ?*anyopaque, _: *vxfw.EventContext, str: []const u8) anyerror!void {
        const ptr = maybe_ptr orelse return;
        const self: *Model = @ptrCast(@alignCast(ptr));

        try self.repopulate_list(str);
    }

    fn onSubmit(maybe_ptr: ?*anyopaque, ctx: *vxfw.EventContext, _: []const u8) !void {
        const ptr = maybe_ptr orelse return;
        const self: *Model = @ptrCast(@alignCast(ptr));

        if (self.filtered.items.len == 0) return;
        if (self.list_view.cursor >= self.filtered.items.len) return;

        const selected_idx = self.filtered.items[self.list_view.cursor].idx;
        const layer = self.layers.items[selected_idx];

        if (layer.sublayers.len > 0) {
            // Navigate into sublayer
            self.current_layer = selected_idx;
            try self.repopulate_list("");
        } else {
            // Leaf layer — select and quit
            self.selected_layer = selected_idx;
            ctx.quit = true;
        }
    }

    fn repopulate_list(self: *Model, fltr: []const u8) !void {
        const arena = self.arena.allocator();
        self.filtered.clearAndFree(arena);
        _ = self.arena.reset(.free_all);

        for (self.layers.items[self.current_layer].sublayers) |sub_idx| {
            const layer = self.layers.items[sub_idx];
            const spans = try filter(arena, layer.name, fltr) orelse continue;

            try self.filtered.append(arena, .{
                .rich_text = .{ .text = spans },
                .idx = sub_idx,
            });
        }

        self.list_view.scroll.top = 0;
        self.list_view.scroll.offset = 0;
        self.list_view.cursor = 0;
    }
};

fn filter(allocator: Allocator, text: []const u8, fltr: []const u8) !?[]TextSpan {
    var spans: std.ArrayList(TextSpan) = .empty;

    if (fltr.len == 0) {
        const span: TextSpan = .{ .text = text };
        try spans.append(allocator, span);
        return try spans.toOwnedSlice(allocator);
    }

    var i: usize = 0;
    var iter = vaxis.unicode.graphemeIterator(fltr);
    while (iter.next()) |g| {
        if (std.mem.indexOfPos(u8, text, i, g.bytes(fltr))) |byte_pos| {
            const up_to_here: TextSpan = .{ .text = text[i..byte_pos] };
            const match: TextSpan = .{
                .text = text[byte_pos .. byte_pos + g.len],
                .style = .{ .fg = .{ .index = 4 }, .reverse = true },
            };
            try spans.append(allocator, up_to_here);
            try spans.append(allocator, match);
            i = byte_pos + g.len;
        } else return null;
    }
    const up_to_here: TextSpan = .{ .text = text[i..] };
    try spans.append(allocator, up_to_here);

    return try spans.toOwnedSlice(allocator);
}

pub fn run(allocator: Allocator, layers: models.Layers) !?usize {
    var app = try vxfw.App.init(allocator);
    errdefer app.deinit();

    const model: *Model = try .init(allocator, layers);
    defer model.deinit(allocator);

    try app.run(model.widget(), .{});
    app.deinit();

    return model.selected_layer;
}
```

- [ ] **Step 2: Verify compilation**

Run: `zig build 2>&1 | head -20`
Expected: may show errors related to main.zig still importing v1 parser — that's OK, will be fixed in Task 2.

- [ ] **Step 3: Commit**

```bash
git add src/tui.zig
git commit -m "rewrite TUI to navigate Layers instead of Entries"
```

---

### Task 2: Rewrite main.zig

**Files:**
- Modify: `src/main.zig`

- [ ] **Step 1: Rewrite main.zig**

Replace the entire file with:

```zig
const std = @import("std");
const builtin = @import("builtin");
const tui = @import("tui.zig");
const Parser = @import("parser/parser.zig");
const models = @import("parser/models.zig");

const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) {
        std.log.err("Memory leak", .{});
    };
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Usage: ap <file.ap>\n", .{});
        return;
    }

    const path = args[1];

    const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(source);

    const layers = try Parser.parse(allocator, source);
    defer layers.deinit();

    const selected = try tui.run(allocator, layers) orelse return;

    const instructions = try collect_instructions(allocator, layers, selected);
    defer allocator.free(instructions);

    execute_instructions(allocator, instructions);
}

fn collect_instructions(allocator: Allocator, layers: models.Layers, leaf_index: usize) ![]const models.Instruction {
    var slices: std.ArrayList([]const models.Instruction) = .empty;
    defer slices.deinit(allocator);

    var idx: ?usize = leaf_index;
    while (idx) |i| {
        if (layers.items[i].instructions.len > 0) {
            try slices.append(allocator, layers.items[i].instructions);
        }
        idx = layers.items[i].parent;
    }

    // Reverse so root's instructions come first
    std.mem.reverse([]const models.Instruction, slices.items);

    // Flatten into single array
    var total: usize = 0;
    for (slices.items) |s| total += s.len;
    const result = try allocator.alloc(models.Instruction, total);
    var pos: usize = 0;
    for (slices.items) |s| {
        @memcpy(result[pos..][0..s.len], s);
        pos += s.len;
    }

    return result;
}

fn execute_instructions(allocator: Allocator, instructions: []const models.Instruction) void {
    for (instructions) |instr| {
        switch (instr) {
            .open => |url| execute_open(allocator, url),
            .run => |cmd| execute_run(allocator, cmd),
            .print => |text| {
                const stdout = std.io.getStdOut().writer();
                stdout.print("{s}\n", .{text}) catch {};
            },
        }
    }
}

fn execute_open(allocator: Allocator, url: []const u8) void {
    const cmd: []const u8 = switch (builtin.os.tag) {
        .linux => "xdg-open",
        .macos => "open",
        else => {
            std.log.err("unsupported platform for open", .{});
            return;
        },
    };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ cmd, url },
    }) catch |err| {
        std.log.err("open failed: {}", .{err});
        return;
    };
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

fn execute_run(allocator: Allocator, cmd: []const u8) void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "sh", "-c", cmd },
    }) catch |err| {
        std.log.err("run failed: {}", .{err});
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        const stdout = std.io.getStdOut().writer();
        stdout.writeAll(result.stdout) catch {};
    }
    if (result.stderr.len > 0) {
        const stderr = std.io.getStdErr().writer();
        stderr.writeAll(result.stderr) catch {};
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add src/main.zig
git commit -m "rewrite main.zig with CLI args, v2 parser, and instruction execution"
```

---

### Task 3: Delete v1 files and verify build

**Files:**
- Delete: `src/parser.zig`
- Delete: `src/entries.zig`
- Delete: `test.ap`

- [ ] **Step 1: Delete v1 files**

```bash
rm src/parser.zig src/entries.zig test.ap
```

- [ ] **Step 2: Build**

Run: `zig build`
Expected: successful build with no errors. If there are compile errors, they are likely minor Zig API issues in main.zig (e.g., `readFileAlloc`, `argsAlloc`). Fix them.

- [ ] **Step 3: Test with no arguments**

Run: `zig build run`
Expected: prints `Usage: ap <file.ap>` to stderr and exits.

- [ ] **Step 4: Test with v2.ap**

Run: `zig build run -- v2.ap`
Expected: TUI launches showing top-level layers: "accesspoint", "multi word layer", "kubectl". Navigate into "accesspoint" → see "repo", "issues", "issue". Select "repo" → TUI quits and opens `https://github.com/bevicted/accesspoint` in browser.

- [ ] **Step 5: Test run instruction**

Run: `zig build run -- v2.ap`
Navigate: "kubectl" → "help" → select "help". Expected: TUI quits and executes `kubectl help` (or shows an error if kubectl is not installed, which is fine).

- [ ] **Step 6: Test escape navigation**

Run: `zig build run -- v2.ap`
Navigate: "kubectl" → press Escape → should return to top-level layers. Press Escape again at root → nothing happens.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "delete v1 parser, entries, and test.ap"
```

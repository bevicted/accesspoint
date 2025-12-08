const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const Allocator = std.mem.Allocator;
const TextSpan = vxfw.RichText.TextSpan;

const entries = @import("entries.zig");

const DisplayItem = struct {
    rich_text: vxfw.RichText,
    idx: usize,
};

const Model = struct {
    arena: std.heap.ArenaAllocator,
    filtered: std.ArrayList(DisplayItem),
    list_view: vxfw.ListView,
    text_field: vxfw.TextField,
    entries: entries.Entries,
    current_parent: ?usize,
    target_url: ?[]const u8,

    pub fn init(allocator: Allocator, ent: entries.Entries) !*Model {
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
            .entries = ent,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .current_parent = null,
            .target_url = null,
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
                    if (self.current_parent) |p| {
                        self.current_parent = self.entries.parents[p];
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

        const prompt: vxfw.Text = .{ .text = "", .style = .{ .fg = .{ .index = 4 } } };

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

        // empty list
        if (self.list_view.cursor > self.filtered.items.len) {
            return;
        }

        const selected = self.filtered.items[self.list_view.cursor].idx;
        for (self.entries.parents[selected..]) |parent| {
            if (parent == selected) break;
        } else {
            self.target_url = self.entries.items[selected].url orelse "urlless";
            ctx.quit = true;
            return;
        }

        self.current_parent = selected;
        try self.repopulate_list("");
    }

    fn repopulate_list(self: *Model, fltr: []const u8) !void {
        const arena = self.arena.allocator();
        self.filtered.clearAndFree(arena);
        _ = self.arena.reset(.free_all);

        for (0..self.entries.items.len) |idx| {
            if (self.entries.parents[idx] != self.current_parent) {
                continue;
            }

            const e = self.entries.items[idx];
            const text = e.name orelse e.url orelse "nameless";
            const spans = try filter(arena, text, fltr) orelse continue;

            try self.filtered.append(arena, .{
                .rich_text = .{ .text = spans },
                .idx = idx,
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

pub fn run(allocator: Allocator, ent: entries.Entries) !void {
    var app = try vxfw.App.init(allocator);
    errdefer app.deinit();

    const model: *Model = try .init(allocator, ent);
    defer model.deinit(allocator);

    try app.run(model.widget(), .{});
    app.deinit();

    if (model.target_url) |url| {
        _ = try std.posix.write(std.posix.STDOUT_FILENO, url);
        _ = try std.posix.write(std.posix.STDOUT_FILENO, "\n");
    }
}

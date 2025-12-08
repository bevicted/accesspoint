const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const entries = @import("entries.zig");
const Allocator = std.mem.Allocator;

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
                const arena = self.arena.allocator();

                for (0..self.entries.items.len) |idx| {
                    if (self.entries.parents[idx] == self.current_parent) {
                        var spans: std.ArrayList(vxfw.RichText.TextSpan) = .empty;
                        const e = self.entries.items[idx];
                        const span: vxfw.RichText.TextSpan = .{
                            .text = e.name orelse e.url orelse "nameless",
                        };
                        try spans.append(arena, span);
                        try self.filtered.append(arena, .{
                            .rich_text = .{ .text = spans.items },
                            .idx = idx,
                        });
                    }
                }

                return ctx.requestFocus(self.text_field.widget());
            },
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
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
        const arena = self.arena.allocator();
        self.filtered.clearAndFree(arena);
        _ = self.arena.reset(.free_all);

        // Loop each line
        // If our input is only lowercase, we convert the line to lowercase
        // Iterate the input graphemes, looking for them _in order_ in the line
        outer: for (0.., self.entries.items) |idx, entry| {
            if (self.entries.parents[idx] != self.current_parent) {
                continue;
            }

            var spans = std.ArrayList(vxfw.RichText.TextSpan){};
            var i: usize = 0;
            var iter = vaxis.unicode.graphemeIterator(str);
            const text = entry.name orelse entry.url.?;
            while (iter.next()) |g| {
                if (std.mem.indexOfPos(u8, text, i, g.bytes(str))) |byte_pos| {
                    const up_to_here: vxfw.RichText.TextSpan = .{ .text = text[i..byte_pos] };
                    const match: vxfw.RichText.TextSpan = .{
                        .text = text[byte_pos .. byte_pos + g.len],
                        .style = .{ .fg = .{ .index = 4 }, .reverse = true },
                    };
                    try spans.append(arena, up_to_here);
                    try spans.append(arena, match);
                    i = byte_pos + g.len;
                } else continue :outer;
            }
            const up_to_here: vxfw.RichText.TextSpan = .{ .text = text[i..] };
            try spans.append(arena, up_to_here);
            try self.filtered.append(arena, .{
                .rich_text = .{ .text = spans.items },
                .idx = idx,
            });
        }
        self.list_view.scroll.top = 0;
        self.list_view.scroll.offset = 0;
        self.list_view.cursor = 0;
    }

    fn onSubmit(maybe_ptr: ?*anyopaque, ctx: *vxfw.EventContext, _: []const u8) !void {
        const ptr = maybe_ptr orelse return;
        const self: *Model = @ptrCast(@alignCast(ptr));
        const arena = self.arena.allocator();

        if (self.list_view.cursor > self.filtered.items.len) {
            return;
        }

        const selected = self.filtered.items[self.list_view.cursor].idx;
        if (self.entries.children[selected].len < 0) {
            _ = try std.posix.write(std.posix.STDOUT_FILENO, self.entries.items[selected].url orelse "urlless");
            _ = try std.posix.write(std.posix.STDOUT_FILENO, "\n");
            ctx.quit = true;
            return;
        }

        for (self.entries.children[selected]) |c| {
            var spans: std.ArrayList(vxfw.RichText.TextSpan) = .empty;
            const e = self.entries.items[c];
            const span: vxfw.RichText.TextSpan = .{
                .text = e.name orelse e.url orelse "nameless",
            };
            try spans.append(arena, span);
            try self.filtered.append(arena, .{
                .rich_text = .{ .text = spans.items },
                .idx = c,
            });
        }
    }
};

pub fn run(allocator: Allocator, ent: entries.Entries) !void {
    var app = try vxfw.App.init(allocator);
    errdefer app.deinit();

    const model: *Model = try .init(allocator, ent);
    defer model.deinit(allocator);

    try app.run(model.widget(), .{});
    app.deinit();
}

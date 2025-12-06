const std = @import("std");
const builtin = @import("builtin");
const entries = @import("entries.zig");

const Allocator = std.mem.Allocator;

const DELIMITER = if (builtin.os.tag == .windows) '\r' else '\n';

const StackPos = struct {
    idx: usize,
    indent: u8,
    children: std.ArrayList(usize),
};

pub fn parseFile(allocator: Allocator, path: []const u8) !entries.Entries {
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
        return err;
    };
    defer file.close();

    var arena = try allocator.create(std.heap.ArenaAllocator);
    errdefer allocator.destroy(arena);
    arena.* = .init(allocator);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();

    var entry_list: std.ArrayList(entries.Entry) = .empty;
    defer entry_list.deinit(allocator);

    var children: std.ArrayList([]usize) = .empty;
    defer {
        for (children.items) |c| {
            allocator.free(c);
        }
        children.deinit(allocator);
    }

    var parents: std.ArrayList(?usize) = .empty;
    defer parents.deinit(allocator);

    var stack: std.ArrayList(StackPos) = .empty;
    defer stack.deinit(allocator);

    var line_allocator: std.io.Writer.Allocating = .init(allocator);
    defer line_allocator.deinit();

    var r_buf: [4096]u8 = undefined;
    var fr: std.fs.File.Reader = file.reader(&r_buf);
    const r: *std.io.Reader = &fr.interface;

    while (true) {
        const line = readLine(r, &line_allocator) catch |err| {
            if (err == error.EndOfStream) break else return err;
        };

        var indent: u8 = 0;
        for (line) |char| {
            if (char == ' ' or char == '\t') {
                indent += 1;
                continue;
            }
            break;
        }

        const data: entries.Entry = try std.json.parseFromSliceLeaky(entries.Entry, arena_allocator, line[indent..], .{});
        try entry_list.append(allocator, data);
        try children.append(allocator, &.{});
        try parents.append(allocator, null);

        while (stack.items.len > 0 and stack.getLast().indent >= indent) {
            var last = &stack.items[stack.items.len - 1];
            children.items[last.idx] = try last.children.toOwnedSlice(allocator);
            _ = stack.pop();
        }

        if (stack.items.len > 0) {
            var last = &stack.items[stack.items.len - 1];
            try last.children.append(allocator, entry_list.items.len - 1);
            parents.items[parents.items.len - 1] = entry_list.items.len - 1;
        }

        try stack.append(allocator, .{
            .idx = entry_list.items.len - 1,
            .indent = indent,
            .children = .empty,
        });
    }

    for (0..stack.items.len) |i| {
        var pos = stack.items[stack.items.len - 1 - i];
        children.items[pos.idx] = try pos.children.toOwnedSlice(allocator);
    }

    const res = entries.Entries{
        .arena = arena,
        .items = try arena_allocator.alloc(entries.Entry, entry_list.items.len),
        .children = try arena_allocator.alloc([]usize, children.items.len),
        .parents = try arena_allocator.alloc(?usize, parents.items.len),
    };

    @memmove(res.items, entry_list.items);
    @memmove(res.children, children.items);
    @memmove(res.parents, parents.items);

    return res;
}

fn readLine(r: *std.io.Reader, line_allocator: *std.io.Writer.Allocating) std.io.Reader.StreamError![]u8 {
    _ = try r.streamDelimiter(&line_allocator.writer, DELIMITER);
    r.toss(1);
    const line = line_allocator.written();
    line_allocator.clearRetainingCapacity();

    return line;
}

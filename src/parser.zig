const std = @import("std");
const builtin = @import("builtin");
const entries = @import("entries.zig");

const Allocator = std.mem.Allocator;

const DELIMITER = if (builtin.os.tag == .windows) '\r' else '\n';

const StackPos = struct {
    idx: usize,
    indent: u8,
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

    var item_arr: std.ArrayList(entries.Entry) = .empty;
    var parents: std.ArrayList(?usize) = .empty;

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
        try item_arr.append(arena_allocator, data);
        try parents.append(arena_allocator, null);

        while (stack.items.len > 0 and stack.getLast().indent >= indent) {
            _ = stack.pop();
        }

        if (stack.getLastOrNull()) |last| {
            parents.items[parents.items.len - 1] = last.idx;
        }

        try stack.append(allocator, .{
            .idx = item_arr.items.len - 1,
            .indent = indent,
        });
    }

    const res = entries.Entries{
        .arena = arena,
        .items = try item_arr.toOwnedSlice(arena_allocator),
        .parents = try parents.toOwnedSlice(arena_allocator),
    };

    return res;
}

fn readLine(r: *std.io.Reader, line_allocator: *std.io.Writer.Allocating) std.io.Reader.StreamError![]u8 {
    _ = try r.streamDelimiter(&line_allocator.writer, DELIMITER);
    r.toss(1);
    const line = line_allocator.written();
    line_allocator.clearRetainingCapacity();

    return line;
}

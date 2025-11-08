const std = @import("std");
const builtin = @import("builtin");
const tui = @import("tui.zig");

const Allocator = std.mem.Allocator;
const Parsed = std.json.Parsed;

const DELIMITER = if (builtin.os.tag == .windows) '\r' else '\n';

const Entries = struct {
    allocator: Allocator,
    parsed: []Parsed(Entry),
    children: [][]usize,

    pub fn deinit(self: @This()) void {
        for (self.parsed) |p| {
            p.deinit();
        }
        self.allocator.free(self.parsed);

        for (self.children) |c|
            self.allocator.free(c);
        self.allocator.free(self.children);
    }
};

const Entry = struct {
    name: ?[]u8 = null,
    url: ?[]u8 = null,
    id: ?[]u8 = null,
    tags: ?[][]u8 = null,
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) {
        std.log.err("Memory leak", .{});
    };
    const allocator = gpa.allocator();

    const path = "test.ap"; // get from CLI later
    const entries = try parseFile(allocator, path);
    defer entries.deinit();

    for (0.., entries.parsed) |idx, p| {
        std.debug.print("{s} has {d} children: ", .{ p.value.name orelse "nameless", entries.children[idx].len });
        for (entries.children[idx]) |c|
            std.debug.print("{d} ", .{c});
        std.debug.print("\n", .{});
    }

    try tui.run(allocator);
}

const QueuePos = struct {
    idx: usize,
    indent: u8,
    children: std.ArrayList(usize),
};

fn parseFile(allocator: Allocator, path: []const u8) !Entries {
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
        return err;
    };
    defer file.close();

    var parsed: std.ArrayList(Parsed(Entry)) = .empty;
    defer parsed.deinit(allocator);

    var children: std.ArrayList([]usize) = .empty;
    defer children.deinit(allocator);

    var queue: std.ArrayList(QueuePos) = .empty;
    defer queue.deinit(allocator);

    var line_allocator: std.io.Writer.Allocating = .init(allocator);
    defer line_allocator.deinit();

    var r_buf: [4096]u8 = undefined;
    var fr: std.fs.File.Reader = file.reader(&r_buf);
    const r: *std.io.Reader = &fr.interface;

    while (true) {
        const line = readLine(r, &line_allocator) catch |err| {
            if (err == error.EndOfStream) break else return err;
        };

        std.debug.print("line={s}\n", .{line});
        var indent: u8 = 0;
        for (line) |char| {
            if (char == ' ' or char == '\t') {
                indent += 1;
                continue;
            }
            break;
        }

        const data: Parsed(Entry) = try std.json.parseFromSlice(Entry, allocator, line[indent..], .{});
        errdefer data.deinit();
        try parsed.append(allocator, data);
        try children.append(allocator, &.{});

        while (queue.items.len > 0 and queue.getLast().indent >= indent) {
            var last = &queue.items[queue.items.len - 1];
            children.items[last.idx] = try last.children.toOwnedSlice(allocator);
            _ = queue.pop();
        }

        if (queue.items.len > 0) {
            var last = &queue.items[queue.items.len - 1];
            try last.children.append(allocator, parsed.items.len - 1);
        }

        try queue.append(allocator, .{
            .idx = parsed.items.len - 1,
            .indent = indent,
            .children = .empty,
        });
    }

    for (0..queue.items.len) |i| {
        var pos = queue.items[queue.items.len - 1 - i];
        children.items[pos.idx] = try pos.children.toOwnedSlice(allocator);
    }

    return Entries{
        .allocator = allocator,
        .parsed = try parsed.toOwnedSlice(allocator),
        .children = try children.toOwnedSlice(allocator),
    };
}

fn readLine(r: *std.io.Reader, line_allocator: *std.io.Writer.Allocating) std.io.Reader.StreamError![]u8 {
    _ = try r.streamDelimiter(&line_allocator.writer, DELIMITER);
    r.toss(1);
    const line = line_allocator.written();
    line_allocator.clearRetainingCapacity();

    return line;
}

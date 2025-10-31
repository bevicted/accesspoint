const std = @import("std");
const builtin = @import("builtin");
const accesspoint = @import("accesspoint");

const Allocator = std.mem.Allocator;
const Parsed = std.json.Parsed;

const DELIMITER = if (builtin.os.tag == .windows) '\r' else '\n';

const Entries = struct {
    const Self = @This();
    allocator: Allocator,
    parsed: []Parsed(EntryData),
    //items: []Entry,

    pub fn deinit(self: Self) void {
        for (self.parsed) |p| {
            p.deinit();
        }
        self.allocator.free(self.parsed);
    }
};

const EntryData = struct {
    name: ?[]u8 = null,
    url: ?[]u8 = null,
    id: ?[]u8 = null,
    tags: ?[][]u8 = null,
};

const Entry = struct {
    const Self = @This();
    data: *const EntryData,
    children: []*Self,
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

    for (entries.parsed) |p| {
        if (p.value.name) |name| {
            std.debug.print("{s}\n", .{name});
        }
    }

    try accesspoint.bufferedPrint();
}

fn parseFile(allocator: Allocator, path: []const u8) !Entries {
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
        return err;
    };
    defer file.close();

    var parsed: std.ArrayList(Parsed(EntryData)) = .empty;
    defer parsed.deinit(allocator);

    // var entries: std.ArrayList(Entry) = .empty;
    // defer entries.deinit(allocator);

    var queue: std.ArrayList(*Entry) = .empty;
    defer queue.deinit(allocator);

    var indents: std.ArrayList(usize) = .empty;
    defer indents.deinit(allocator);

    var line_allocator: std.io.Writer.Allocating = .init(allocator);
    defer line_allocator.deinit();

    var r_buf: [4096]u8 = undefined;
    var fr: std.fs.File.Reader = file.reader(&r_buf);
    const r: *std.io.Reader = &fr.interface;

    while (true) {
        _ = r.streamDelimiter(&line_allocator.writer, DELIMITER) catch |err| {
            if (err == error.EndOfStream) break else return err;
        };
        r.toss(1);
        const line = line_allocator.written();
        line_allocator.clearRetainingCapacity();

        std.debug.print("now processing: {s}\n", .{line});
        var indent: usize = 0;
        for (line) |char| {
            if (char == ' ' or char == '\t') {
                indent += 1;
                continue;
            }
            break;
        }
        const data: Parsed(EntryData) = try std.json.parseFromSlice(EntryData, allocator, line[indent..], .{});
        errdefer data.deinit();

        try parsed.append(allocator, data);

        var e = Entry{
            .data = &data.value,
            .children = &[0]*Entry{},
        };
        defer allocator.free(e.children);

        while (indents.items.len > 0 and indents.getLast() >= indent) {
            _ = indents.pop();
            _ = queue.pop();
        }

        if (queue.getLastOrNull()) |p| {
            std.debug.print("has parent\n", .{});
            if (p.data.name) |n|
                std.debug.print("parent: {s}\n", .{n});
            p.children = try std.mem.concat(allocator, *Entry, &.{ p.children, &.{&e} });
            for (p.children) |c|
                if (c.data.url) |n|
                    std.debug.print("{s}\n", .{n});
        }

        try indents.append(allocator, indent);
        try queue.append(allocator, &e);
        //try entries.append(allocator, e);
    }

    return Entries{
        .allocator = allocator,
        .parsed = try parsed.toOwnedSlice(allocator),
        //.items = try entries.toOwnedSlice(allocator),
    };
}

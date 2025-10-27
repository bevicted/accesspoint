const std = @import("std");
const builtin = @import("builtin");
const accesspoint = @import("accesspoint");

const Allocator = std.mem.Allocator;

const DELIMITER = if (builtin.os.tag == .windows) '\r' else '\n';

const Entries = struct {
    allocator: *const Allocator,
    parsed: []std.json.Parsed(Entry),

    pub fn deinit(self: @This()) void {
        for (self.parsed) |p| {
            p.deinit();
        }
        self.allocator.free(self.parsed);
    }
};

const Entry = struct {
    name: ?[]u8 = null,
    url: ?[]u8 = null,
    id: ?[]u8 = null,
    tags: ?[][]u8 = null,
    children: ?[]@This() = null,
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

    var entries: std.ArrayList(std.json.Parsed(Entry)) = .empty;
    defer entries.deinit(allocator);

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

        std.debug.print("{s}\n", .{line});
        var indent: usize = 0;
        for (line) |char| {
            switch (char) {
                ' ' => indent += 1,
                '\t' => indent += 4,
                else => break,
            }
        }
        const parsed: std.json.Parsed(Entry) = try std.json.parseFromSlice(Entry, allocator, line[indent..], .{});
        errdefer parsed.deinit();
        try entries.append(allocator, parsed);
    }

    return Entries{
        .allocator = &allocator,
        .parsed = try entries.toOwnedSlice(allocator),
    };
}

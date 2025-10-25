const std = @import("std");
const builtin = @import("builtin");
const accesspoint = @import("accesspoint");

const DELIMITER = if (builtin.os.tag == .windows) '\r' else '\n';

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
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
        return err;
    };
    defer file.close();

    var line_allocator: std.io.Writer.Allocating = .init(allocator);
    defer line_allocator.deinit();

    var r_buf: [4096]u8 = undefined;
    var fr: std.fs.File.Reader = file.reader(&r_buf);
    const r: *std.io.Reader = &fr.interface;
    //var entries: []Entry = undefined;

    while (true) {
        _ = r.streamDelimiter(&line_allocator.writer, DELIMITER) catch |err| {
            if (err == error.EndOfStream) break else return err;
        };
        r.toss(1);
        const line = line_allocator.written();
        line_allocator.clearRetainingCapacity();

        std.debug.print("{s}\n", .{line});
        var indent: usize = undefined;
        for (0.., line) |idx, char| {
            if (char != ' ') {
                indent = idx;
                break;
            }
        }
        const parsed: std.json.Parsed(Entry) = try std.json.parseFromSlice(Entry, allocator, line[indent..], .{});
        const entry = parsed.value;
        if (entry.name) |name| {
            std.debug.print("{s}\n", .{name});
        }
        parsed.deinit();
    }

    try accesspoint.bufferedPrint();
}

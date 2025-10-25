const std = @import("std");
const builtin = @import("builtin");
const accesspoint = @import("accesspoint");

const DELIMITER = if (builtin.os.tag == .windows) '\r' else '\n';

pub fn main() !void {
    // const gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    // defer if (gpa.deinit() == .leak) {
    //     std.log.err("Memory leak", .{});
    // };
    // const allocator = gpa.allocator();

    const path = "test.ap"; // get from CLI later
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
        return err;
    };
    defer file.close();

    var w_buf: [4096]u8 = undefined;
    var w: std.io.Writer = .fixed(&w_buf);
    var r_buf: [4096]u8 = undefined;
    var fr = file.reader(&r_buf);
    const r = &fr.interface;

    while (true) {
        _ = r.streamDelimiter(&w, DELIMITER) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        r.toss(1);
        try w.flush();
        std.debug.print("{s}\n", .{w.buffered()});
        w.end = 0;
    }

    try accesspoint.bufferedPrint();
}

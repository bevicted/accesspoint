const std = @import("std");
const tui = @import("tui.zig");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) {
        std.log.err("Memory leak", .{});
    };
    const allocator = gpa.allocator();

    const path = "test.ap"; // get from CLI later
    const entries = try parser.parseFile(allocator, path);
    defer entries.deinit();

    try tui.run(allocator, entries);
}

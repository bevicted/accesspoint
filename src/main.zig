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

    for (0.., entries.parsed) |idx, p| {
        std.debug.print("{s} has {d} children: ", .{ p.value.name orelse "nameless", entries.children[idx].len });
        for (entries.children[idx]) |c|
            std.debug.print("{d} ", .{c});
        std.debug.print("\n", .{});
    }

    try tui.run(allocator);
}

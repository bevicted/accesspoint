const std = @import("std");

const Allocator = std.mem.Allocator;
const Parsed = std.json.Parsed;

pub const Entries = struct {
    allocator: Allocator,
    items: []Parsed(Entry),
    children: [][]usize,

    pub fn deinit(self: @This()) void {
        for (self.items) |p| {
            p.deinit();
        }
        self.allocator.free(self.items);

        for (self.children) |c|
            self.allocator.free(c);
        self.allocator.free(self.children);
    }
};

pub const Entry = struct {
    name: ?[]u8 = null,
    url: ?[]u8 = null,
    id: ?[]u8 = null,
    tags: ?[][]u8 = null,
};

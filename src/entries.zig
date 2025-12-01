const std = @import("std");

pub const Entries = struct {
    arena: *std.heap.ArenaAllocator,
    items: []Entry,
    children: [][]usize,

    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
    }
};

pub const Entry = struct {
    name: ?[]u8 = null,
    url: ?[]u8 = null,
    id: ?[]u8 = null,
    tags: ?[][]u8 = null,
};

const std = @import("std");

pub const Instruction = union(enum) {
    open: []const u8,
    run: []const u8,
    print: []const u8,
};

pub const Variable = struct {
    name: []const u8,
    value: []const u8,
};

pub const Layer = struct {
    name: []const u8,
    parent: ?usize,
    sublayers: []usize,
    variables: []Variable,
    instructions: []Instruction,
};

pub const Layers = struct {
    arena: *std.heap.ArenaAllocator,
    items: []Layer,

    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
    }
};

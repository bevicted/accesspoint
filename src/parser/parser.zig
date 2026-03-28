const std = @import("std");
const Scanner = @import("scanner.zig");
const Token = @import("token.zig");
const models = @import("models.zig");

scanner: Scanner,
current: Token = .{},
layers: std.ArrayList(models.Layer),
arena: std.mem.Allocator,

const Self = @This();

const Error = error{
    UnexpectedToken,
    ExpectedIdentifier,
    ExpectedEqual,
    ExpectedLeftBrace,
    ExpectedDoubleRightBrace,
    UnexpectedRightBrace,
    UnexpectedEof,
    UnresolvedVariable,
    ScanError,
    OutOfMemory,
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) Error!models.Layers {
    var arena = try allocator.create(std.heap.ArenaAllocator);
    errdefer allocator.destroy(arena);
    arena.* = .init(allocator);
    errdefer arena.deinit();
    const arena_alloc = arena.allocator();

    var self = Self{
        .scanner = Scanner.init(source),
        .layers = .empty,
        .arena = arena_alloc,
    };

    // Create root layer
    try self.layers.append(arena_alloc, .{
        .name = "",
        .parent = null,
        .sublayers = &.{},
        .variables = &.{},
        .instructions = &.{},
    });

    try self.advance();
    try self.parse_body(0, true);

    return .{
        .arena = arena,
        .items = self.layers.items,
    };
}

fn advance(self: *Self) Error!void {
    self.current = self.scanner.next();
    if (self.current.kind == .ERROR) return error.ScanError;
}

fn is_identifier_like(kind: Token.Kind) bool {
    return switch (kind) {
        .IDENTIFIER, .LAYER, .LET, .OPEN, .RUN, .PRINT => true,
        else => false,
    };
}

fn parse_body(self: *Self, layer_index: usize, is_root: bool) Error!void {
    var sublayers: std.ArrayList(usize) = .empty;
    var variables: std.ArrayList(models.Variable) = .empty;
    var instructions: std.ArrayList(models.Instruction) = .empty;

    while (true) {
        switch (self.current.kind) {
            .LAYER => {
                try self.advance();
                const idx = try self.parse_layer(layer_index);
                try sublayers.append(self.arena, idx);
            },
            .LET => {
                try self.advance();
                const v = try self.parse_let(layer_index);
                try variables.append(self.arena, v);
            },
            .OPEN, .RUN, .PRINT => {
                const kind = self.current.kind;
                const instr = try self.parse_instruction(layer_index, kind);
                try instructions.append(self.arena, instr);
            },
            .RIGHT_BRACE => {
                if (is_root) return error.UnexpectedRightBrace;
                try self.advance();
                break;
            },
            .EOF => {
                if (!is_root) return error.UnexpectedEof;
                break;
            },
            else => return error.UnexpectedToken,
        }
    }

    self.layers.items[layer_index].sublayers = try sublayers.toOwnedSlice(self.arena);
    self.layers.items[layer_index].variables = try variables.toOwnedSlice(self.arena);
    self.layers.items[layer_index].instructions = try instructions.toOwnedSlice(self.arena);
}

fn parse_layer(self: *Self, parent_index: usize) Error!usize {
    // self.current is first token after LAYER keyword
    var name_parts: std.ArrayList([]const u8) = .empty;
    while (is_identifier_like(self.current.kind)) {
        try name_parts.append(self.arena, self.current.lexeme);
        try self.advance();
    }

    if (self.current.kind != .LEFT_BRACE) return error.ExpectedLeftBrace;
    try self.advance(); // consume {

    // Join name parts with spaces
    const name = try self.join_with_spaces(name_parts.items);

    const new_index = self.layers.items.len;
    try self.layers.append(self.arena, .{
        .name = name,
        .parent = parent_index,
        .sublayers = &.{},
        .variables = &.{},
        .instructions = &.{},
    });

    try self.parse_body(new_index, false);

    return new_index;
}

fn parse_let(self: *Self, layer_index: usize) Error!models.Variable {
    // self.current should be the variable name
    if (!is_identifier_like(self.current.kind)) return error.ExpectedIdentifier;
    const name = self.current.lexeme;

    try self.advance();
    if (self.current.kind != .EQUAL) return error.ExpectedEqual;

    const value = try self.resolve_value(layer_index);
    try self.advance(); // prime next structural token

    return .{ .name = name, .value = value };
}

fn parse_instruction(self: *Self, layer_index: usize, kind: Token.Kind) Error!models.Instruction {
    // self.current is OPEN/RUN/PRINT keyword
    const value = try self.resolve_value(layer_index);
    try self.advance(); // prime next structural token

    return switch (kind) {
        .OPEN => .{ .open = value },
        .RUN => .{ .run = value },
        .PRINT => .{ .print = value },
        else => unreachable,
    };
}

fn resolve_value(self: *Self, layer_index: usize) Error![]const u8 {
    var buf: std.ArrayList(u8) = .empty;

    self.scanner.skip_spaces();

    while (true) {
        const tok = self.scanner.next_value();
        switch (tok.kind) {
            .VALUE_TEXT => try buf.appendSlice(self.arena, tok.lexeme),
            .DOUBLE_LEFT_BRACE => {
                const id = self.scanner.next();
                if (!is_identifier_like(id.kind)) return error.ExpectedIdentifier;
                const close = self.scanner.next();
                if (close.kind != .DOUBLE_RIGHT_BRACE) return error.ExpectedDoubleRightBrace;
                const resolved = self.lookup_variable(layer_index, id.lexeme) orelse return error.UnresolvedVariable;
                try buf.appendSlice(self.arena, resolved);
            },
            .NEWLINE, .EOF => break,
            else => return error.UnexpectedToken,
        }
    }

    return buf.items;
}

fn lookup_variable(self: *Self, layer_index: usize, name: []const u8) ?[]const u8 {
    var idx: ?usize = layer_index;
    while (idx) |i| {
        const layer = self.layers.items[i];
        for (layer.variables) |v| {
            if (std.mem.eql(u8, v.name, name)) return v.value;
        }
        idx = layer.parent;
    }
    return null;
}

fn join_with_spaces(self: *Self, parts: [][]const u8) Error![]const u8 {
    if (parts.len == 0) return "";
    if (parts.len == 1) return parts[0];
    var total: usize = parts.len - 1; // spaces
    for (parts) |p| total += p.len;
    const result = try self.arena.alloc(u8, total);
    var pos: usize = 0;
    for (parts, 0..) |p, i| {
        if (i > 0) {
            result[pos] = ' ';
            pos += 1;
        }
        @memcpy(result[pos..][0..p.len], p);
        pos += p.len;
    }
    return result;
}

test "parse empty input" {
    const result = try parse(std.testing.allocator, "");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    try std.testing.expectEqualStrings("", result.items[0].name);
    try std.testing.expectEqual(@as(?usize, null), result.items[0].parent);
    try std.testing.expectEqual(@as(usize, 0), result.items[0].sublayers.len);
}

test "parse simple layer" {
    const result = try parse(std.testing.allocator,
        \\layer foo {
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.items.len);
    // root
    try std.testing.expectEqual(@as(usize, 1), result.items[0].sublayers.len);
    try std.testing.expectEqual(@as(usize, 1), result.items[0].sublayers[0]);
    // layer foo
    try std.testing.expectEqualStrings("foo", result.items[1].name);
    try std.testing.expectEqual(@as(?usize, 0), result.items[1].parent);
}

test "parse nested layers" {
    const result = try parse(std.testing.allocator,
        \\layer outer {
        \\    layer inner {
        \\    }
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 3), result.items.len);
    // root -> outer -> inner
    try std.testing.expectEqual(@as(usize, 1), result.items[0].sublayers.len);
    try std.testing.expectEqual(@as(usize, 1), result.items[1].sublayers.len);
    try std.testing.expectEqual(@as(usize, 2), result.items[1].sublayers[0]);
    try std.testing.expectEqualStrings("inner", result.items[2].name);
    try std.testing.expectEqual(@as(?usize, 1), result.items[2].parent);
}

test "parse multi-word layer name" {
    const result = try parse(std.testing.allocator,
        \\layer multi word name {
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("multi word name", result.items[1].name);
}

test "parse multiple layers" {
    const result = try parse(std.testing.allocator,
        \\layer a {
        \\}
        \\layer b {
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 3), result.items.len);
    try std.testing.expectEqual(@as(usize, 2), result.items[0].sublayers.len);
}

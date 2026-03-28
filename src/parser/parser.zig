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
    try self.parse_body(0, true, &.{});

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

fn parse_body(self: *Self, layer_index: usize, is_root: bool, parent_vars: []const models.Variable) Error!void {
    var sublayers: std.ArrayList(usize) = .empty;
    var variables: std.ArrayList(models.Variable) = .empty;
    var instructions: std.ArrayList(models.Instruction) = .empty;

    while (true) {
        switch (self.current.kind) {
            .LAYER => {
                try self.advance();
                const idx = try self.parse_layer(layer_index, variables.items);
                try sublayers.append(self.arena, idx);
            },
            .LET => {
                try self.advance();
                const v = try self.parse_let(layer_index, variables.items, parent_vars);
                try variables.append(self.arena, v);
            },
            .OPEN, .RUN, .PRINT => {
                const kind = self.current.kind;
                const instr = try self.parse_instruction(layer_index, kind, variables.items, parent_vars);
                try instructions.append(self.arena, instr);
            },
            .RIGHT_BRACE => {
                if (is_root) {
                    std.log.err("line {d}: unexpected '}}' at top level", .{self.current.line});
                    return error.UnexpectedRightBrace;
                }
                try self.advance();
                break;
            },
            .EOF => {
                if (!is_root) {
                    std.log.err("line {d}: unexpected end of file, expected '}}'", .{self.current.line});
                    return error.UnexpectedEof;
                }
                break;
            },
            else => {
                std.log.err("line {d}: unexpected token", .{self.current.line});
                return error.UnexpectedToken;
            },
        }
    }

    self.layers.items[layer_index].sublayers = try sublayers.toOwnedSlice(self.arena);
    self.layers.items[layer_index].variables = try variables.toOwnedSlice(self.arena);
    self.layers.items[layer_index].instructions = try instructions.toOwnedSlice(self.arena);
}

fn parse_layer(self: *Self, parent_index: usize, parent_vars: []const models.Variable) Error!usize {
    // self.current is first token after LAYER keyword
    var name_parts: std.ArrayList([]const u8) = .empty;
    while (is_identifier_like(self.current.kind)) {
        try name_parts.append(self.arena, self.current.lexeme);
        try self.advance();
    }

    if (name_parts.items.len == 0) {
        std.log.err("line {d}: expected layer name", .{self.current.line});
        return error.ExpectedIdentifier;
    }

    if (self.current.kind != .LEFT_BRACE) {
        std.log.err("line {d}: expected '{{'", .{self.current.line});
        return error.ExpectedLeftBrace;
    }
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

    try self.parse_body(new_index, false, parent_vars);

    return new_index;
}

fn parse_let(self: *Self, layer_index: usize, current_vars: []const models.Variable, parent_vars: []const models.Variable) Error!models.Variable {
    // self.current should be the variable name
    if (!is_identifier_like(self.current.kind)) {
        std.log.err("line {d}: expected variable name", .{self.current.line});
        return error.ExpectedIdentifier;
    }
    const name = self.current.lexeme;

    try self.advance();
    if (self.current.kind != .EQUAL) {
        std.log.err("line {d}: expected '='", .{self.current.line});
        return error.ExpectedEqual;
    }

    const value = try self.resolve_value(layer_index, current_vars, parent_vars);
    try self.advance(); // prime next structural token

    return .{ .name = name, .value = value };
}

fn parse_instruction(self: *Self, layer_index: usize, kind: Token.Kind, current_vars: []const models.Variable, parent_vars: []const models.Variable) Error!models.Instruction {
    // self.current is OPEN/RUN/PRINT keyword
    const value = try self.resolve_value(layer_index, current_vars, parent_vars);
    try self.advance(); // prime next structural token

    return switch (kind) {
        .OPEN => .{ .open = value },
        .RUN => .{ .run = value },
        .PRINT => .{ .print = value },
        else => unreachable,
    };
}

fn resolve_value(self: *Self, layer_index: usize, current_vars: []const models.Variable, parent_vars: []const models.Variable) Error![]const u8 {
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
                const resolved = self.lookup_variable(layer_index, id.lexeme, current_vars, parent_vars) orelse {
                    std.log.err("line {d}: unresolved variable '{s}'", .{ id.line, id.lexeme });
                    return error.UnresolvedVariable;
                };
                try buf.appendSlice(self.arena, resolved);
            },
            .NEWLINE, .EOF => break,
            else => return error.UnexpectedToken,
        }
    }

    return try buf.toOwnedSlice(self.arena);
}

fn lookup_variable(self: *Self, layer_index: usize, name: []const u8, current_vars: []const models.Variable, parent_vars: []const models.Variable) ?[]const u8 {
    // First search the in-progress variables for the current layer
    for (current_vars) |v| {
        if (std.mem.eql(u8, v.name, name)) return v.value;
    }
    // Then search parent's in-progress variables
    for (parent_vars) |v| {
        if (std.mem.eql(u8, v.name, name)) return v.value;
    }
    // Then walk the parent chain (skip current layer since we already searched current_vars)
    var idx: ?usize = self.layers.items[layer_index].parent;
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

test "parse let binding" {
    const result = try parse(std.testing.allocator,
        \\let x = hello world
    );
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.items[0].variables.len);
    try std.testing.expectEqualStrings("x", result.items[0].variables[0].name);
    try std.testing.expectEqualStrings("hello world", result.items[0].variables[0].value);
}

test "parse let with interpolation" {
    const result = try parse(std.testing.allocator,
        \\let base = hello
        \\let full = {{base}} world
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("hello", result.items[0].variables[0].value);
    try std.testing.expectEqualStrings("hello world", result.items[0].variables[1].value);
}

test "parse variable scope chain" {
    const result = try parse(std.testing.allocator,
        \\let x = parent_val
        \\layer child {
        \\    let y = {{x}} extended
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("parent_val extended", result.items[1].variables[0].value);
}

test "parse variable shadowing" {
    const result = try parse(std.testing.allocator,
        \\let x = original
        \\layer child {
        \\    let x = shadowed
        \\    open {{x}}
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("shadowed", result.items[1].instructions[0].open);
}

test "parse let with keyword name" {
    const result = try parse(std.testing.allocator,
        \\let layer = myvalue
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("layer", result.items[0].variables[0].name);
    try std.testing.expectEqualStrings("myvalue", result.items[0].variables[0].value);
}

test "parse open instruction" {
    const result = try parse(std.testing.allocator,
        \\layer foo {
        \\    open https://example.com
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.items[1].instructions.len);
    try std.testing.expectEqualStrings("https://example.com", result.items[1].instructions[0].open);
}

test "parse run instruction" {
    const result = try parse(std.testing.allocator,
        \\layer foo {
        \\    run echo hello
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("echo hello", result.items[1].instructions[0].run);
}

test "parse instruction with interpolation" {
    const result = try parse(std.testing.allocator,
        \\let url = https://example.com
        \\layer foo {
        \\    open {{url}}/path
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("https://example.com/path", result.items[1].instructions[0].open);
}

test "parse full v2.ap" {
    const source =
        \\let var1 = some value
        \\let var2 = {{var1}} resolved
        \\// this is a comment
        \\
        \\layer accesspoint {
        \\    let repo = https://github.com/bevicted/accesspoint
        \\
        \\    layer repo {
        \\        open {{repo}}
        \\    }
        \\    layer issues {
        \\        open {{repo}}/issues
        \\    }
        \\    layer issue {
        \\        open {{repo}}/issues/42
        \\    }
        \\}
        \\
        \\layer multi word layer {
        \\    open my other repo
        \\}
        \\
        \\layer kubectl {
        \\    let cmd = kubectl
        \\
        \\    layer help {
        \\        run {{cmd}} help
        \\    }
        \\    layer pod {
        \\        let pod = my-pod
        \\        run {{cmd}} get pod {{pod}}
        \\        run {{cmd}} logs -f {{pod}}
        \\    }
        \\    layer get {
        \\        let cmd = {{cmd}} get
        \\        layer pod {
        \\            let cmd = {{cmd}} pod
        \\            let pod_cmd = describe
        \\            run {{cmd}} {{pod_cmd}}
        \\        }
        \\    }
        \\}
    ;

    const result = try parse(std.testing.allocator, source);
    defer result.deinit();

    // 11 layers: root + 10 named
    try std.testing.expectEqual(@as(usize, 11), result.items.len);

    // Root (index 0)
    try std.testing.expectEqual(@as(usize, 3), result.items[0].sublayers.len);
    try std.testing.expectEqualStrings("some value", result.items[0].variables[0].value);
    try std.testing.expectEqualStrings("some value resolved", result.items[0].variables[1].value);

    // accesspoint (index 1)
    try std.testing.expectEqualStrings("accesspoint", result.items[1].name);
    try std.testing.expectEqual(@as(usize, 3), result.items[1].sublayers.len);
    try std.testing.expectEqualStrings("https://github.com/bevicted/accesspoint", result.items[1].variables[0].value);

    // repo (index 2)
    try std.testing.expectEqualStrings("https://github.com/bevicted/accesspoint", result.items[2].instructions[0].open);

    // issues (index 3)
    try std.testing.expectEqualStrings("https://github.com/bevicted/accesspoint/issues", result.items[3].instructions[0].open);

    // issue (index 4)
    try std.testing.expectEqualStrings("https://github.com/bevicted/accesspoint/issues/42", result.items[4].instructions[0].open);

    // multi word layer (index 5)
    try std.testing.expectEqualStrings("multi word layer", result.items[5].name);
    try std.testing.expectEqualStrings("my other repo", result.items[5].instructions[0].open);

    // kubectl (index 6)
    try std.testing.expectEqualStrings("kubectl", result.items[6].name);
    try std.testing.expectEqual(@as(usize, 3), result.items[6].sublayers.len);

    // help (index 7)
    try std.testing.expectEqualStrings("kubectl help", result.items[7].instructions[0].run);

    // pod (index 8)
    try std.testing.expectEqualStrings("kubectl get pod my-pod", result.items[8].instructions[0].run);
    try std.testing.expectEqualStrings("kubectl logs -f my-pod", result.items[8].instructions[1].run);

    // get (index 9)
    try std.testing.expectEqualStrings("kubectl get", result.items[9].variables[0].value);

    // get > pod (index 10)
    try std.testing.expectEqualStrings("kubectl get pod", result.items[10].variables[0].value);
    try std.testing.expectEqualStrings("kubectl get pod describe", result.items[10].instructions[0].run);
}

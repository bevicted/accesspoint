const std = @import("std");
const Token = @import("token.zig");
const Scanner = @import("scanner.zig");
const Self = @This();

const ParseError = error{
    ExpectedExpresion,
    ExpectedLeftBrace,
    ExpectedRightBrace,
    ExpectedVariableName,
};

const Layer = struct {
    name: []const u8,
    sublayers: []usize,
    instructions: [][]const u8,
};

scanner: Scanner,
current: Token,

pub fn init(source: []const u8) Self {
    return Self{
        .scanner = .init(source),
        .current = .{},
    };
}

inline fn check(self: *Self, kind: Token.Kind) bool {
    return self.current.kind == kind;
}

fn consume(self: *Self, kind: Token.Kind, err: ParseError) ParseError!Token {
    if (self.check(kind)) {
        return self.advance();
    }

    return err;
}

fn layer_declaration(self: *Self) !Layer {}

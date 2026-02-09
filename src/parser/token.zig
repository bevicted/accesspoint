const std = @import("std");

const TokenKind = enum {
    LEFT_BRACE,
    RIGHT_BRACE,
    SLASH,

    EQUAL,

    // Literals.
    IDENTIFIER,
    STRING,

    // Keywords.
    LAYER,
    LET,
    OPEN,
    PRINT,
    RUN,

    EOF,
};

const Token = struct {
    kind: TokenKind,
    value: []const u8,
    lexeme: []const u8,
    literal: struct {},
    line: u16,

    pub fn String(self: @This()) ![]const u8 {
        var b: []u8 = undefined;
        try std.fmt.bufPrint(&b, "{} {} {}", .{ self.kind, self.lexeme, self.literal });
        return b;
    }
};

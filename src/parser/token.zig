const std = @import("std");

const TokenType = enum {
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    SEMICOLON,
    SLASH,

    // One or two character tokens.
    EQUAL,

    // Literals.
    IDENTIFIER,
    STRING,

    // Keywords.
    AND,
    FALSE,
    OR,
    PRINT,
    TRUE,
    VAR,

    EOF,
};

const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    literal: struct {},
    line: i16,

    pub fn String(self: @This()) ![]const u8 {
        var b: []u8 = undefined;
        try std.fmt.bufPrint(&b, "{} {} {}", .{ self.type, self.lexeme, self.literal });
        return b;
    }
};

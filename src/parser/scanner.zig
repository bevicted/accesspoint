const std = @import("std");
pub const Token = @import("token.zig");

source: []const u8,
current_token_start: usize,
current_token_end: usize,
line: usize,

const Self = @This();

pub fn init(source: []const u8) Self {
    return .{
        .source = source,
        .current_token_start = 0,
        .current_token_end = 0,
        .line = 1,
    };
}

fn is_at_end(self: *Self) bool {
    return self.current_token_end >= self.source.len;
}

fn peek(self: *Self) ?u8 {
    if (self.is_at_end()) return null;
    return self.source[self.current_token_end];
}

fn peek_next(self: *Self) ?u8 {
    if (self.current_token_end + 1 >= self.source.len) return null;
    return self.source[self.current_token_end + 1];
}

fn advance(self: *Self) void {
    self.current_token_end += 1;
}

fn make_token(self: *Self, kind: Token.Kind) Token {
    return .{
        .kind = kind,
        .lexeme = self.source[self.current_token_start..self.current_token_end],
        .line = self.line,
    };
}

fn make_error(self: *Self, message: []const u8) Token {
    return .{
        .kind = .ERROR,
        .lexeme = message,
        .line = self.line,
    };
}

fn skip_line(self: *Self) void {
    while (self.peek()) |c| {
        if (c == '\n') return;
        self.advance();
    }
}

fn skip_whitespace(self: *Self) void {
    while (self.peek()) |c| {
        switch (c) {
            ' ', '\t', '\r' => self.advance(),
            '\n' => {
                self.line += 1;
                self.advance();
            },
            '/' => {
                if (self.peek_next() == '/') {
                    self.skip_line();
                } else return;
            },
            else => return,
        }
    }
}

pub fn skip_spaces(self: *Self) void {
    while (self.peek()) |c| {
        switch (c) {
            ' ', '\t' => self.advance(),
            else => return,
        }
    }
}

fn match_keyword(self: *Self) Token.Kind {
    const len = self.current_token_end - self.current_token_start;
    const lexeme = self.source[self.current_token_start..self.current_token_end];
    return switch (len) {
        3 => {
            if (std.mem.eql(u8, lexeme, "let")) return .LET;
            if (std.mem.eql(u8, lexeme, "run")) return .RUN;
            return .IDENTIFIER;
        },
        4 => if (std.mem.eql(u8, lexeme, "open")) .OPEN else .IDENTIFIER,
        5 => {
            if (std.mem.eql(u8, lexeme, "layer")) return .LAYER;
            if (std.mem.eql(u8, lexeme, "print")) return .PRINT;
            return .IDENTIFIER;
        },
        else => .IDENTIFIER,
    };
}

fn is_alpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn is_alpha_numeric(c: u8) bool {
    return is_alpha(c) or (c >= '0' and c <= '9');
}

pub fn next(self: *Self) Token {
    self.skip_whitespace();
    self.current_token_start = self.current_token_end;

    if (self.is_at_end()) return self.make_token(.EOF);

    const c = self.source[self.current_token_end];
    self.advance();

    if (c == '{') {
        if (self.peek() == '{') {
            self.advance();
            return self.make_token(.DOUBLE_LEFT_BRACE);
        }
        return self.make_token(.LEFT_BRACE);
    }
    if (c == '}') {
        if (self.peek() == '}') {
            self.advance();
            return self.make_token(.DOUBLE_RIGHT_BRACE);
        }
        return self.make_token(.RIGHT_BRACE);
    }
    if (c == '=') return self.make_token(.EQUAL);
    if (is_alpha(c)) {
        while (self.peek()) |nc| {
            if (!is_alpha_numeric(nc)) break;
            self.advance();
        }
        return self.make_token(self.match_keyword());
    }
    return self.make_error("Unexpected character");
}

pub fn next_value(self: *Self) Token {
    self.current_token_start = self.current_token_end;

    if (self.is_at_end()) return self.make_token(.EOF);

    const c = self.source[self.current_token_end];

    if (c == '{' and self.peek_next() == '{') {
        self.advance();
        self.advance();
        return self.make_token(.DOUBLE_LEFT_BRACE);
    }

    if (c == '\n') {
        self.advance();
        self.line += 1;
        return self.make_token(.NEWLINE);
    }

    // Consume VALUE_TEXT until {{ or \n or EOF
    self.advance();
    while (self.peek()) |nc| {
        if (nc == '\n') break;
        if (nc == '{' and self.peek_next() == '{') break;
        self.advance();
    }

    return self.make_token(.VALUE_TEXT);
}

test "scan keywords" {
    var s = Self.init("layer let open run print");
    try std.testing.expectEqual(.LAYER, s.next().kind);
    try std.testing.expectEqual(.LET, s.next().kind);
    try std.testing.expectEqual(.OPEN, s.next().kind);
    try std.testing.expectEqual(.RUN, s.next().kind);
    try std.testing.expectEqual(.PRINT, s.next().kind);
    try std.testing.expectEqual(.EOF, s.next().kind);
}

test "scan identifiers" {
    var s = Self.init("foo bar_baz abc123");
    const t1 = s.next();
    try std.testing.expectEqual(.IDENTIFIER, t1.kind);
    try std.testing.expectEqualStrings("foo", t1.lexeme);
    const t2 = s.next();
    try std.testing.expectEqual(.IDENTIFIER, t2.kind);
    try std.testing.expectEqualStrings("bar_baz", t2.lexeme);
    const t3 = s.next();
    try std.testing.expectEqual(.IDENTIFIER, t3.kind);
    try std.testing.expectEqualStrings("abc123", t3.lexeme);
}

test "scan single braces" {
    var s = Self.init("{ }");
    try std.testing.expectEqual(.LEFT_BRACE, s.next().kind);
    try std.testing.expectEqual(.RIGHT_BRACE, s.next().kind);
    try std.testing.expectEqual(.EOF, s.next().kind);
}

test "scan double braces" {
    var s = Self.init("{{ }}");
    try std.testing.expectEqual(.DOUBLE_LEFT_BRACE, s.next().kind);
    try std.testing.expectEqual(.DOUBLE_RIGHT_BRACE, s.next().kind);
    try std.testing.expectEqual(.EOF, s.next().kind);
}

test "scan equal" {
    var s = Self.init("=");
    try std.testing.expectEqual(.EQUAL, s.next().kind);
}

test "skip comments" {
    var s = Self.init("// comment\nlayer");
    try std.testing.expectEqual(.LAYER, s.next().kind);
}

test "skip blank lines" {
    var s = Self.init("\n\n  \n  layer");
    try std.testing.expectEqual(.LAYER, s.next().kind);
}

test "next_value plain text" {
    var s = Self.init("https://example.com/path\n");
    const tok = s.next_value();
    try std.testing.expectEqual(.VALUE_TEXT, tok.kind);
    try std.testing.expectEqualStrings("https://example.com/path", tok.lexeme);
    try std.testing.expectEqual(.NEWLINE, s.next_value().kind);
}

test "next_value with interpolation" {
    var s = Self.init("{{var}}/path\n");
    try std.testing.expectEqual(.DOUBLE_LEFT_BRACE, s.next_value().kind);
    // switch to next() for identifier inside interpolation
    const id = s.next();
    try std.testing.expectEqual(.IDENTIFIER, id.kind);
    try std.testing.expectEqualStrings("var", id.lexeme);
    // switch to next() for closing }}
    try std.testing.expectEqual(.DOUBLE_RIGHT_BRACE, s.next().kind);
    // back to next_value for remaining text
    const text = s.next_value();
    try std.testing.expectEqual(.VALUE_TEXT, text.kind);
    try std.testing.expectEqualStrings("/path", text.lexeme);
    try std.testing.expectEqual(.NEWLINE, s.next_value().kind);
}

test "next_value empty" {
    var s = Self.init("\n");
    try std.testing.expectEqual(.NEWLINE, s.next_value().kind);
}

test "next_value eof" {
    var s = Self.init("");
    try std.testing.expectEqual(.EOF, s.next_value().kind);
}

test "skip_spaces" {
    var s = Self.init("   hello\n");
    s.skip_spaces();
    const tok = s.next_value();
    try std.testing.expectEqual(.VALUE_TEXT, tok.kind);
    try std.testing.expectEqualStrings("hello", tok.lexeme);
}

test "line tracking" {
    var s = Self.init("layer\nlayer\nlayer");
    const t1 = s.next();
    try std.testing.expectEqual(@as(usize, 1), t1.line);
    const t2 = s.next();
    try std.testing.expectEqual(@as(usize, 2), t2.line);
    const t3 = s.next();
    try std.testing.expectEqual(@as(usize, 3), t3.line);
}

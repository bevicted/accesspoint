const std = @import("std");
const Token = @import("token.zig");

const assert = std.debug.assert;

const Scanner = struct {
    source: []const u8,
    current_idx: u64,
    line: usize,

    const Self = @This();

    pub fn init(source: []const u8) Scanner {
        return Scanner{
            .source = source,
            .current_idx = 0,
            .line = 1,
        };
    }

    fn is_at_end(self: Self) bool {
        return self.current_idx >= self.source.len;
    }

    fn advance(self: Self) void {
        self.current_idx += 1;
    }

    fn get_current_char(self: Self) ?u8 {
        if (self.is_at_end()) return null;
        return self.source[self.current_idx];
    }

    fn get_next_char(self: Self) ?u8 {
        if (self.current_idx + 1 >= self.source.len) return null;
        return self.source[self.current_idx + 1];
    }

    fn match_char(self: Self, target_char: u8) bool {
        if (self.is_at_end()) return false;
        if (self.get_current_char() != target_char) return false;
        self.current_idx += 1;
        return true;
    }

    fn make_token(self: Self, kind: Token.Kind) Token {
        return .{
            .kind = kind,
            .lexeme = self.source[0..self.current_idx],
            .line = self.line,
        };
    }

    fn make_error(self: Self, message: []const u8) Token {
        return .{
            .kind = .ERROR,
            .lexeme = message,
            .line = self.line,
        };
    }

    fn skip_line(self: Self) void {
        while (self.get_current_char() != '\n' and !self.is_at_end()) {
            self.advance();
        }
    }

    fn skip_whitespace(self: Self) void {
        while (true) {
            switch (self.get_current_char()) {
                ' ', '\t', '\r' => self.advance(),
                '\n' => {
                    self.line += 1;
                    self.advance();
                },
                '/' => {
                    if (self.get_next_char() == '/') {
                        self.skip_line();
                        continue;
                    }
                    return;
                },
                else => return,
            }
        }
    }

    fn check_keyword(self: Self, offset: usize, str: []const u8, kind: Token.Kind) Token.Kind {
        if (self.current_idx != str.len + offset) return .IDENTIFIER;
        const source_slice = self.source[offset..self.current_idx];
        assert(source_slice.len == str.len);
        return if (std.mem.eql(u8, source_slice, str)) kind else .IDENTIFIER;
    }
};

fn is_aplha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        c == '_';
}

fn is_digit(c: u8) bool {
    return c >= '0' and c <= '9';
}

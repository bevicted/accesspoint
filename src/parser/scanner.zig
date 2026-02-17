const std = @import("std");
const Token = @import("token.zig");

const Scanner = struct {
    source: []const u8,
    current_token_start: usize,
    current_token_end: usize,
    line: usize,

    const Self = @This();

    pub fn init(source: []const u8) Scanner {
        return Scanner{
            .source = source,
            .current_token_start = 0,
            .current_token_end = 0,
            .line = 1,
        };
    }

    fn is_at_end(self: Self) bool {
        return self.current_token_end >= self.source.len;
    }

    fn advance(self: Self) void {
        self.current_token_end += 1;
    }

    fn get_current_char(self: Self) ?u8 {
        if (self.is_at_end()) return null;
        return self.source[self.current_token_end];
    }

    fn get_next_char(self: Self) ?u8 {
        if (self.current_token_end + 1 >= self.source.len) return null;
        return self.source[self.current_token_end + 1];
    }

    fn match_char(self: Self, target_char: u8) bool {
        if (self.is_at_end()) return false;
        if (self.get_current_char() != target_char) return false;
        self.current_token_end += 1;
        return true;
    }

    fn make_token(self: Self, kind: Token.Kind) Token {
        return .{
            .kind = kind,
            .lexeme = self.source[self.current_token_start..self.current_token_end],
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

    fn match_keyword(self: Self, offset: usize, target: []const u8, target_kind: Token.Kind) Token.Kind {
        std.debug.assert(target.len > offset);
        const source_slice = self.source[self.current_token_start + offset .. target.len - offset];
        return if (std.mem.eql(u8, source_slice, target[offset..])) target_kind else .IDENTIFIER;
    }

    fn match_identifier(self: Self) Token.Kind {
        return switch (self.source[self.current_token_start]) {
            'l' => switch (self.source[self.current_token_start + 1]) {
                'a' => self.match_keyword(2, "layer", .LAYER),
                'e' => self.match_keyword(2, "let", .LET),
            },
            'o' => self.match_keyword(1, "open", .OPEN),
            'p' => self.match_keyword(1, "print", .PRINT),
            'r' => self.match_keyword(1, "run", .RUN),
            else => .IDENTIFIER,
        };
    }

    fn consume_identifier(self: Self) Token {
        while (is_alpha_numeric(self.get_current_char())) self.advance();
        return self.make_token(self.match_identifier());
    }
};

fn is_alpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        c == '_';
}

fn is_digit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn is_alpha_numeric(c: u8) bool {
    return is_alpha(c) or is_digit(c);
}

const std = @import("std");
const Token = @import("token.zig");
const Scanner = @import("scanner.zig");
const Self = @This();

const Precedence = enum(u1) {
    NONE,
    ASSIGNMENT,
};

scanner: Scanner,
previous: Token,
current: Token,

pub fn init(source: []const u8) Self {
    return Self{
        .scanner = .init(source),
        .current = .{},
    };
}

inline fn is_kind(self: *Self, kind: Token.Kind) bool {
    return self.current.kind == kind;
}

fn advance(self: *Self) !void {
    self.previous = self.current;

    while (true) {
        self.current = self.scanner.next();
        if (!self.is_kind(.ERROR)) break;
        try self.errorAtCurrent(self.current.lexeme);
    }
}

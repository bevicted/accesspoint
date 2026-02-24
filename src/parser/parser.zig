const std = @import("std");
const Token = @import("token.zig");
const Self = @This();

allocator: std.mem.Allocator,
tokens: std.ArrayList,
current: usize,

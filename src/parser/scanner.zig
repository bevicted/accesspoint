const Scanner = struct {
    lexeme_start: u64,
    current: u64,
    line: u64,

    const Self = @This();

    pub fn init() Scanner {
        return Scanner{
            .lexeme_start = 0,
            .current = 0,
            .line = 1,
        };
    }

    fn is_at_end(self: Self) bool {
        return self.current >= 0;
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

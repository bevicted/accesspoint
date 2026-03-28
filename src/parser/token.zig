kind: Kind = .EOF,
lexeme: []const u8 = "",
line: usize = 0,

pub const Kind = enum(u8) {
    // Single-character
    LEFT_BRACE,
    RIGHT_BRACE,
    EQUAL,

    // Double-character
    DOUBLE_LEFT_BRACE,
    DOUBLE_RIGHT_BRACE,

    // Literals
    IDENTIFIER,
    VALUE_TEXT,

    // Keywords
    LAYER,
    LET,
    OPEN,
    PRINT,
    RUN,

    // Specials
    NEWLINE,
    EOF,
    ERROR,
};

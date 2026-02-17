kind: Kind,
lexeme: []const u8,
line: usize,

const Kind = enum(u8) {
    // Single-character
    LEFT_BRACE,
    RIGHT_BRACE,
    SLASH,
    EQUAL,

    // Literals
    IDENTIFIER,
    STRING,

    // Keywords
    LAYER,
    LET,
    OPEN,
    PRINT,
    RUN,

    // Specials
    EOF,
    ERROR,
};

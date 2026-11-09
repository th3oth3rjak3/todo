const token_module = @import("../lexer/token.zig");
const TokenKind = token_module.TokenKind;

pub const BinaryOperation = enum {
    add,
    sub,
    mul,
    div,

    less,
    less_equal,
    greater,
    greater_equal,
    equal_equal,
    bang_equal,

    const Self = @This();

    pub fn fromTokenKind(kind: TokenKind) Self {
        return switch (kind) {
            TokenKind.plus => .add,
            TokenKind.minus => .sub,
            TokenKind.star => .mul,
            TokenKind.slash => .div,
            TokenKind.less => .less,
            TokenKind.less_equal => .less_equal,
            TokenKind.greater => .greater,
            TokenKind.greater_equal => .greater_equal,
            TokenKind.equal_equal => .equal_equal,
            TokenKind.bang_equal => .bang_equal,
            else => unreachable,
        };
    }
};

pub const UnaryOperation = enum {
    negate,
    logical_not,

    const Self = @This();

    pub fn fromTokenKind(kind: TokenKind) Self {
        return switch (kind) {
            TokenKind.minus => .negate,
            TokenKind.bang => .logical_not,
            else => unreachable,
        };
    }
};

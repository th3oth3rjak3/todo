const token_module = @import("token.zig");
const TokenKind = token_module.TokenKind;

pub const Keyword = struct {
    lexeme: []const u8,
    kind: TokenKind,
};

pub const keywords = [_]Keyword{
    .{ .lexeme = "pub", .kind = .keyword_pub },
    .{ .lexeme = "record", .kind = .keyword_record },
    .{ .lexeme = "true", .kind = .keyword_true },
    .{ .lexeme = "false", .kind = .keyword_false },
};

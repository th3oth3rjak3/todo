const token_module = @import("token.zig");
const TokenKind = token_module.TokenKind;

pub const Keyword = struct {
    lexeme: []const u8,
    kind: TokenKind,
};

pub const keywords = [_]Keyword{
    .{ .lexeme = "public", .kind = .keyword_public },
    .{ .lexeme = "record", .kind = .keyword_record },
};

const std = @import("std");
const source = @import("../source/span.zig");

/// The kind of lexical token.
pub const TokenKind = enum {
    identifier,
    integer,
    float,
    hex_integer,
    binary_integer,
    exponent_float,
    string,
    character,

    keyword_public,
    keyword_record,

    left_brace,
    right_brace,
    colon,
    comma,
    left_paren,
    right_paren,
    semicolon,

    equal,
    equal_equal,
    bang,
    bang_equal,

    plus,
    minus,
    star,
    slash,

    less,
    less_equal,
    greater,
    greater_equal,

    doc_comment,
    eof,
};

/// Represents a lexical token found in source code.
pub const Token = struct {
    /// The kind of token.
    kind: TokenKind,

    /// The location of the token in its source file.
    span: source.Span,

    /// Returns the source text covered by this token.
    ///
    /// The returned slice borrows from the original source text.
    pub fn lexeme(self: Token, source_text: []const u8) []const u8 {
        std.debug.assert(self.span.start <= self.span.end);
        std.debug.assert(self.span.start <= source_text.len);
        std.debug.assert(self.span.end <= source_text.len);
        return source_text[self.span.start..self.span.end];
    }
};

test "lexeme returns the source text covered by the token span" {
    const source_text = "let answer = 42;";

    const token = Token{
        .kind = .integer,
        .span = .{
            .source = .{ .value = 1 },
            .start = 13,
            .end = 15,
        },
    };

    try std.testing.expectEqualStrings("42", token.lexeme(source_text));
}

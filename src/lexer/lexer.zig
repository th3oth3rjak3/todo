const std = @import("std");
const source = @import("../source/source.zig");
const SourceId = source.SourceId;
const token = @import("token.zig");
const Token = token.Token;

/// Scans a single source file and produces lexical tokens.
pub const Lexer = struct {
    /// Identifies the source file being scanned.
    source_id: SourceId,

    /// The source text being scanned.
    ///
    /// The caller owns this memory and must keep it alive for the
    /// lifetime of the lexer.
    source_text: []const u8,

    /// The byte offset of the next character to be scanned.
    position: usize,

    /// Creates a lexer for the given source file.
    pub fn init(source_id: SourceId, source_text: []const u8) Lexer {
        return .{
            .source_id = source_id,
            .source_text = source_text,
            .position = 0,
        };
    }

    /// Scans and returns the next token.
    ///
    /// Repeated calls return tokens in source order. Once the end of
    /// the source is reached, subsequent calls return EOF.
    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespace();

        const start = self.position;

        if (self.isAtEnd()) {
            return .{
                .kind = .eof,
                .span = .{
                    .source = self.source_id,
                    .start = start,
                    .end = start,
                },
            };
        }

        return .{
            .kind = .eof,
            .span = .{
                .source = self.source_id,
                .start = start,
                .end = start,
            },
        };
    }

    /// Skips whitespace characters.
    fn skipWhitespace(self: *Lexer) void {
        while (!self.isAtEnd()) {
            switch (self.source_text[self.position]) {
                ' ', '\t', '\n', '\r' => self.position += 1,
                else => return,
            }
        }
    }

    /// Returns whether the end of the source has been reached.
    fn isAtEnd(self: *const Lexer) bool {
        return self.position >= self.source_text.len;
    }
};

test "empty source produces EOF" {
    var lexer = Lexer.init(.{ .value = 1 }, "");

    const result = lexer.nextToken();

    try std.testing.expectEqual(token.Kind.eof, result.kind);
    try std.testing.expectEqual(@as(usize, 0), result.span.start);
    try std.testing.expectEqual(@as(usize, 0), result.span.end);
}

const std = @import("std");

const source_module = @import("../source/source.zig");
const SourceId = source_module.SourceId;

const token_module = @import("token.zig");
const Token = token_module.Token;
const TokenKind = token_module.TokenKind;

const diagnostic_module = @import("../diagnostics/diagnostic.zig");
const Diagnostic = diagnostic_module.Diagnostic;

const keyword_module = @import("keyword.zig");
const keywords = keyword_module.keywords;
const Keyword = keyword_module.Keyword;

/// The result of attempting to scan another token.
pub const TokenResult = union(enum) {
    /// A valid token was scanned successfully.
    token: Token,
    /// An error occurred and is reported in this
    /// diagnostic.
    diagnostic: Diagnostic,
};

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
    /// Scans and returns the next token.
    ///
    /// Skips whitespace and returns an error if an invalid character is encountered.
    pub fn nextToken(self: *Lexer) TokenResult {
        self.skipWhitespace();

        const start = self.position;

        if (self.isAtEnd()) {
            return .{
                .token = .{
                    .kind = .eof,
                    .span = .{
                        .source = self.source_id,
                        .start = start,
                        .end = start,
                    },
                },
            };
        }

        const char = self.source_text[self.position];

        if (isIdentifierStart(char)) {
            return .{
                .token = self.scanIdentifier(),
            };
        }

        if (isDigit(char)) {
            return .{
                .token = self.scanNumber(),
            };
        }

        self.position += 1;

        return .{
            .diagnostic = .{
                .severity = .err,
                .message = "Invalid character",
                .span = .{
                    .source = self.source_id,
                    .start = start,
                    .end = self.position,
                },
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

    /// Returns whether a byte is an ASCII letter.
    fn isAlpha(char: u8) bool {
        return (char >= 'a' and char <= 'z') or
            (char >= 'A' and char <= 'Z');
    }

    /// Returns whether a byte is an ASCII digit.
    fn isDigit(char: u8) bool {
        return char >= '0' and char <= '9';
    }

    /// Returns whether a byte is valid at the beginning of an identifier.
    fn isIdentifierStart(char: u8) bool {
        return isAlpha(char) or char == '_';
    }

    /// Returns whether a byte is valid after the first character of an identifier.
    fn isIdentifier(char: u8) bool {
        return isIdentifierStart(char) or isDigit(char);
    }

    /// Scans an identifier or keyword.
    fn scanIdentifier(self: *Lexer) Token {
        const start = self.position;

        while (!self.isAtEnd() and isIdentifier(self.source_text[self.position])) {
            self.position += 1;
        }

        const lexeme = self.source_text[start..self.position];

        return .{
            .kind = identifierKind(lexeme),
            .span = .{
                .source = self.source_id,
                .start = start,
                .end = self.position,
            },
        };
    }

    /// Returns the keyword kind for a lexeme, or `.identifier` if it isn't a keyword.
    fn identifierKind(lexeme: []const u8) TokenKind {
        for (keywords) |keyword| {
            if (std.mem.eql(u8, lexeme, keyword.lexeme)) {
                return keyword.kind;
            }
        }

        return .identifier;
    }

    /// Scans a numeric literal, distinguishing integers from floating-point literals.
    fn scanNumber(self: *Lexer) Token {
        const start = self.position;

        while (!self.isAtEnd() and isDigit(self.source_text[self.position])) {
            self.position += 1;
        }

        var kind: TokenKind = .integer;

        if (!self.isAtEnd() and self.source_text[self.position] == '.') {
            const dot_position = self.position;
            const next_position = dot_position + 1;

            if (next_position < self.source_text.len and
                isDigit(self.source_text[next_position]))
            {
                kind = .float;
                self.position += 1;

                while (!self.isAtEnd() and isDigit(self.source_text[self.position])) {
                    self.position += 1;
                }
            }
        }

        return .{
            .kind = kind,
            .span = .{
                .source = self.source_id,
                .start = start,
                .end = self.position,
            },
        };
    }
};

test "empty source produces EOF" {
    var lexer = Lexer.init(.{ .value = 1 }, "");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.eof, tok.kind);
            try std.testing.expectEqual(@as(usize, 0), tok.span.start);
            try std.testing.expectEqual(@as(usize, 0), tok.span.end);
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans integer literals" {
    var lexer = Lexer.init(.{ .value = 1 }, "42");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.integer, tok.kind);
            try std.testing.expectEqualStrings("42", tok.lexeme(lexer.source_text));
            try std.testing.expectEqual(@as(usize, 0), tok.span.start);
            try std.testing.expectEqual(@as(usize, 2), tok.span.end);
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans floating-point literals" {
    var lexer = Lexer.init(.{ .value = 1 }, "3.14");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.float, tok.kind);
            try std.testing.expectEqualStrings("3.14", tok.lexeme(lexer.source_text));
            try std.testing.expectEqual(@as(usize, 0), tok.span.start);
            try std.testing.expectEqual(@as(usize, 4), tok.span.end);
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans identifiers" {
    var lexer = Lexer.init(.{ .value = 1 }, "person");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.identifier, tok.kind);
            try std.testing.expectEqualStrings("person", tok.lexeme(lexer.source_text));
            try std.testing.expectEqual(@as(usize, 0), tok.span.start);
            try std.testing.expectEqual(@as(usize, 6), tok.span.end);
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans identifiers containing underscores and digits" {
    var lexer = Lexer.init(.{ .value = 1 }, "_person2");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.identifier, tok.kind);
            try std.testing.expectEqualStrings("_person2", tok.lexeme(lexer.source_text));
            try std.testing.expectEqual(@as(usize, 0), tok.span.start);
            try std.testing.expectEqual(@as(usize, 8), tok.span.end);
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans pub keyword" {
    var lexer = Lexer.init(.{ .value = 1 }, "pub");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.keyword_pub, tok.kind);
            try std.testing.expectEqualStrings("pub", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans struct keyword" {
    var lexer = Lexer.init(.{ .value = 1 }, "struct");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.keyword_struct, tok.kind);
            try std.testing.expectEqualStrings("struct", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "keyword prefixes are identifiers" {
    var lexer = Lexer.init(.{ .value = 1 }, "public structure");

    const first = lexer.nextToken();
    const second = lexer.nextToken();

    switch (first) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.identifier, tok.kind);
            try std.testing.expectEqualStrings("public", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }

    switch (second) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.identifier, tok.kind);
            try std.testing.expectEqualStrings("structure", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

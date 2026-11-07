const std = @import("std");

const source_module = @import("../source/source.zig");
const SourceId = source_module.SourceId;

const token_module = @import("token.zig");
const Token = token_module.Token;
const TokenKind = token_module.TokenKind;

const diagnostic_module = @import("../diagnostics/diagnostic.zig");
const Diagnostic = diagnostic_module.Diagnostic;
const Severity = diagnostic_module.Severity;

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
        while (true) {
            self.skipWhitespace();

            if (self.isAtEnd()) {
                const position = self.position;
                return .{
                    .token = self.makeToken(.eof, position, position),
                };
            }

            if (self.source_text[self.position] == '/' and
                self.position + 1 < self.source_text.len and
                self.source_text[self.position + 1] == '/')
            {
                if (self.scanComment()) |doc_token| {
                    return .{ .token = doc_token };
                }

                continue;
            }

            break;
        }

        const char = self.source_text[self.position];

        if (isIdentifierStart(char)) {
            return .{ .token = self.scanIdentifier() };
        }

        if (isDigit(char)) {
            return .{ .token = self.scanNumber() };
        }

        if (char == '"') return self.scanString();
        if (char == '\'') return self.scanCharacter();

        return self.scanPunctuationOrOperator();
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

    fn scanPunctuationOrOperator(self: *Lexer) TokenResult {
        const start = self.position;
        const char = self.source_text[self.position];

        self.position += 1;

        const kind: ?TokenKind = switch (char) {
            '{' => .left_brace,
            '}' => .right_brace,
            '(' => .left_paren,
            ')' => .right_paren,
            ':' => .colon,
            ',' => .comma,
            ';' => .semicolon,

            '+' => .plus,
            '-' => .minus,
            '*' => .star,
            '/' => .slash,

            '=' => if (self.match('=')) .equal_equal else .equal,
            '!' => if (self.match('=')) .bang_equal else .bang,
            '<' => if (self.match('=')) .less_equal else .less,
            '>' => if (self.match('=')) .greater_equal else .greater,

            else => null,
        };

        if (kind) |value| {
            return .{
                .token = self.makeToken(value, start, self.position),
            };
        }

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

    /// Consumes the next character if it matches the expected character.
    fn match(self: *Lexer, expected: u8) bool {
        if (self.isAtEnd() or self.source_text[self.position] != expected) {
            return false;
        }

        self.position += 1;
        return true;
    }

    fn makeToken(
        self: *Lexer,
        kind: TokenKind,
        start: usize,
        end: usize,
    ) Token {
        return .{
            .kind = kind,
            .span = .{
                .source = self.source_id,
                .start = start,
                .end = end,
            },
        };
    }

    /// Scans a line comment, returning a token if it is a documentation comment.
    fn scanComment(self: *Lexer) ?Token {
        const start = self.position;

        // Consume the two slashes.
        self.position += 2;

        // A third slash identifies a documentation comment.
        if (!self.isAtEnd() and self.source_text[self.position] == '/') {
            self.position += 1;

            while (!self.isAtEnd() and self.source_text[self.position] != '\n') {
                self.position += 1;
            }

            return self.makeToken(.doc_comment, start, self.position);
        }

        // Consume an ordinary comment.
        while (!self.isAtEnd() and self.source_text[self.position] != '\n') {
            self.position += 1;
        }

        return null;
    }

    /// Scans a string literal, including its opening and closing quotes.
    fn scanString(self: *Lexer) TokenResult {
        const start = self.position;
        self.position += 1; // Skip opening double quote.

        while (!self.isAtEnd()) {
            const char = self.source_text[self.position];

            switch (char) {
                '"' => {
                    self.position += 1;
                    return .{ .token = self.makeToken(.string, start, self.position) };
                },
                '\\' => {
                    self.position += 1;
                    if (self.scanEscapeSequence()) |diagnostic| {
                        return .{ .diagnostic = diagnostic };
                    }
                },
                '\n', '\r' => {
                    return .{ .diagnostic = self.makeDiagnostic(
                        "Unterminated string literal",
                        start,
                        self.position,
                    ) };
                },
                else => {
                    if (self.advanceCodePoint()) |diagnostic| {
                        return .{ .diagnostic = diagnostic };
                    }
                },
            }
        }

        return .{ .diagnostic = self.makeDiagnostic(
            "Unterminated string literal",
            start,
            self.position,
        ) };
    }

    /// Scans a character literal, including its opening and closing quotes.
    fn scanCharacter(self: *Lexer) TokenResult {
        const start = self.position;
        self.position += 1; // Skip opening single quote.

        if (self.isAtEnd() or self.source_text[self.position] == '\n' or
            self.source_text[self.position] == '\r' or
            self.source_text[self.position] == '\'')
        {
            return .{ .diagnostic = self.makeDiagnostic(
                "Expected character",
                start,
                self.position,
            ) };
        }

        if (self.source_text[self.position] == '\\') {
            self.position += 1;
            if (self.scanEscapeSequence()) |diagnostic| {
                return .{ .diagnostic = diagnostic };
            }
        } else {
            if (self.advanceCodePoint()) |diagnostic| {
                return .{ .diagnostic = diagnostic };
            }
        }

        if (self.isAtEnd() or self.source_text[self.position] != '\'') {
            return .{ .diagnostic = self.makeDiagnostic(
                "Expected closing quote after character",
                start,
                self.position,
            ) };
        }

        self.position += 1;
        return .{ .token = self.makeToken(.character, start, self.position) };
    }

    /// Consumes an escape sequence. Returns null when valid, or a diagnostic.
    fn scanEscapeSequence(self: *Lexer) ?Diagnostic {
        if (self.isAtEnd()) {
            return self.makeDiagnostic(
                "Incomplete escape sequence",
                self.position - 1,
                self.position,
            );
        }

        const start = self.position - 1;
        const char = self.source_text[self.position];
        self.position += 1;

        switch (char) {
            '0', 'n', 'r', 't', '\\', '\'', '"' => return null,
            else => return self.makeDiagnostic(
                "Invalid escape sequence",
                start,
                self.position,
            ),
        }
    }

    fn makeDiagnostic(self: *Lexer, message: []const u8, start: usize, end: usize) Diagnostic {
        return .{
            .severity = .err,
            .message = message,
            .span = .{
                .source = self.source_id,
                .start = start,
                .end = end,
            },
        };
    }

    /// Decodes and consumes one UTF-8 code point.
    fn advanceCodePoint(self: *Lexer) ?Diagnostic {
        const start = self.position;
        const first_byte = self.source_text[self.position];

        const byte_length = std.unicode.utf8ByteSequenceLength(first_byte) catch {
            self.position += 1;
            return self.makeDiagnostic("Invalid UTF-8 sequence", start, self.position);
        };

        const length: usize = @intCast(byte_length);
        const remaining = self.source_text[self.position..];

        if (remaining.len < length) {
            self.position = self.source_text.len;
            return self.makeDiagnostic("Incomplete UTF-8 sequence", start, self.position);
        }

        const decoded = switch (byte_length) {
            1 => @as(u21, first_byte),
            2 => std.unicode.utf8Decode2(remaining[0..2].*) catch {
                self.position += 1;
                return self.makeDiagnostic("Invalid UTF-8 sequence", start, self.position);
            },
            3 => std.unicode.utf8Decode3(remaining[0..3].*) catch {
                self.position += 1;
                return self.makeDiagnostic("Invalid UTF-8 sequence", start, self.position);
            },
            4 => std.unicode.utf8Decode4(remaining[0..4].*) catch {
                self.position += 1;
                return self.makeDiagnostic("Invalid UTF-8 sequence", start, self.position);
            },
            else => unreachable,
        };

        _ = decoded;
        self.position += length;
        return null;
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

test "scans public keyword" {
    var lexer = Lexer.init(.{ .value = 1 }, "public");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.keyword_public, tok.kind);
            try std.testing.expectEqualStrings("public", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans record keyword" {
    var lexer = Lexer.init(.{ .value = 1 }, "record");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.keyword_record, tok.kind);
            try std.testing.expectEqualStrings("record", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "keyword prefixes are identifiers" {
    var lexer = Lexer.init(.{ .value = 1 }, "publicly recorded");

    const first = lexer.nextToken();
    const second = lexer.nextToken();

    switch (first) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.identifier, tok.kind);
            try std.testing.expectEqualStrings("publicly", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }

    switch (second) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.identifier, tok.kind);
            try std.testing.expectEqualStrings("recorded", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans left brace" {
    var lexer = Lexer.init(.{ .value = 1 }, "{");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.left_brace, tok.kind);
            try std.testing.expectEqualStrings("{", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans right brace" {
    var lexer = Lexer.init(.{ .value = 1 }, "}");

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.right_brace, tok.kind);
            try std.testing.expectEqualStrings("}", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans parentheses" {
    var lexer = Lexer.init(.{ .value = 1 }, "()");

    const left = lexer.nextToken();
    const right = lexer.nextToken();

    switch (left) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.left_paren, tok.kind);
            try std.testing.expectEqualStrings("(", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }

    switch (right) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.right_paren, tok.kind);
            try std.testing.expectEqualStrings(")", tok.lexeme(lexer.source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans colon comma and semicolon" {
    var lexer = Lexer.init(.{ .value = 1 }, ":,;");

    const expected = [_]TokenKind{
        .colon,
        .comma,
        .semicolon,
    };

    for (expected) |expected_kind| {
        const result = lexer.nextToken();

        switch (result) {
            .token => |tok| {
                try std.testing.expectEqual(expected_kind, tok.kind);
            },
            .diagnostic => return error.UnexpectedDiagnostic,
        }
    }
}

test "scans multiple punctuation characters in sequence" {
    var lexer = Lexer.init(.{ .value = 1 }, "{ name: value, }");

    const expected = [_]TokenKind{
        .left_brace,
        .identifier,
        .colon,
        .identifier,
        .comma,
        .right_brace,
        .eof,
    };

    for (expected) |expected_kind| {
        const result = lexer.nextToken();

        switch (result) {
            .token => |tok| {
                try std.testing.expectEqual(expected_kind, tok.kind);
            },
            .diagnostic => return error.UnexpectedDiagnostic,
        }
    }
}

test "invalid character produces diagnostic" {
    var lexer = Lexer.init(.{ .value = 1 }, "@");

    const result = lexer.nextToken();

    switch (result) {
        .token => return error.UnexpectedToken,
        .diagnostic => |diag| {
            try std.testing.expectEqual(Severity.err, diag.severity);
            try std.testing.expectEqualStrings("Invalid character", diag.message);
            try std.testing.expectEqual(@as(usize, 0), diag.span.start);
            try std.testing.expectEqual(@as(usize, 1), diag.span.end);
        },
    }
}

test "scans operators" {
    const TestCase = struct {
        lexeme: []const u8,
        kind: TokenKind,
    };

    const cases = [_]TestCase{
        .{ .lexeme = "=", .kind = .equal },
        .{ .lexeme = "==", .kind = .equal_equal },
        .{ .lexeme = "!", .kind = .bang },
        .{ .lexeme = "!=", .kind = .bang_equal },
        .{ .lexeme = "+", .kind = .plus },
        .{ .lexeme = "-", .kind = .minus },
        .{ .lexeme = "*", .kind = .star },
        .{ .lexeme = "/", .kind = .slash },
        .{ .lexeme = "<", .kind = .less },
        .{ .lexeme = "<=", .kind = .less_equal },
        .{ .lexeme = ">", .kind = .greater },
        .{ .lexeme = ">=", .kind = .greater_equal },
    };

    for (cases) |case| {
        var lexer = Lexer.init(.{ .value = 1 }, case.lexeme);
        const result = lexer.nextToken();

        switch (result) {
            .token => |tok| {
                try std.testing.expectEqual(case.kind, tok.kind);
                try std.testing.expectEqualStrings(case.lexeme, tok.lexeme(lexer.source_text));
            },
            .diagnostic => return error.UnexpectedDiagnostic,
        }
    }
}

test "scans adjacent operators independently" {
    var lexer = Lexer.init(.{ .value = 1 }, "===!=");

    const expected = [_]TokenKind{
        .equal_equal,
        .equal,
        .bang_equal,
    };

    for (expected) |expected_kind| {
        const result = lexer.nextToken();

        switch (result) {
            .token => |tok| {
                try std.testing.expectEqual(expected_kind, tok.kind);
            },
            .diagnostic => return error.UnexpectedDiagnostic,
        }
    }
}

test "scans documentation comment" {
    const source_text = "/// Documents a declaration.";

    var lexer = Lexer.init(.{ .value = 1 }, source_text);
    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.doc_comment, tok.kind);
            try std.testing.expectEqualStrings(
                source_text,
                tok.lexeme(source_text),
            );
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "skips ordinary line comment" {
    const source_text = "// An ordinary comment\n42";

    var lexer = Lexer.init(.{ .value = 1 }, source_text);
    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.integer, tok.kind);
            try std.testing.expectEqualStrings("42", tok.lexeme(source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans documentation comment followed by token" {
    const source_text = "/// Documentation\n42";

    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const doc_result = lexer.nextToken();
    const integer_result = lexer.nextToken();

    switch (doc_result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.doc_comment, tok.kind);
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }

    switch (integer_result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.integer, tok.kind);
            try std.testing.expectEqualStrings("42", tok.lexeme(source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans empty documentation comment" {
    const source_text = "///";

    var lexer = Lexer.init(.{ .value = 1 }, source_text);
    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.doc_comment, tok.kind);
            try std.testing.expectEqualStrings("///", tok.lexeme(source_text));
            try std.testing.expectEqual(@as(usize, 0), tok.span.start);
            try std.testing.expectEqual(@as(usize, 3), tok.span.end);
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans documentation comment at EOF" {
    const source_text = "/// Documentation";

    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.doc_comment, tok.kind);
            try std.testing.expectEqualStrings(source_text, tok.lexeme(source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }

    const eof_result = lexer.nextToken();

    switch (eof_result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.eof, tok.kind);
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "skips ordinary comment at EOF" {
    const source_text = "// An ordinary comment";

    var lexer = Lexer.init(.{ .value = 1 }, source_text);
    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.eof, tok.kind);
            try std.testing.expectEqual(source_text.len, tok.span.start);
            try std.testing.expectEqual(source_text.len, tok.span.end);
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "skips consecutive ordinary comments" {
    const source_text =
        \\// First comment
        \\// Second comment
        \\// Third comment
        \\42
    ;

    var lexer = Lexer.init(.{ .value = 1 }, source_text);
    const result = lexer.nextToken();

    switch (result) {
        .token => |tok| {
            try std.testing.expectEqual(TokenKind.integer, tok.kind);
            try std.testing.expectEqualStrings("42", tok.lexeme(source_text));
        },
        .diagnostic => return error.UnexpectedDiagnostic,
    }
}

test "scans division operator followed by ordinary comment" {
    const source_text = "a / // comment\nb";

    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const expected = [_]TokenKind{
        .identifier,
        .slash,
        .identifier,
        .eof,
    };

    for (expected) |expected_kind| {
        const result = lexer.nextToken();

        switch (result) {
            .token => |tok| {
                try std.testing.expectEqual(expected_kind, tok.kind);
            },
            .diagnostic => return error.UnexpectedDiagnostic,
        }
    }
}

test "scan empty string" {
    var lexer = Lexer.init(.{ .value = 1 }, "\"\"");
    const result = lexer.nextToken();

    try std.testing.expectEqual(TokenKind.string, result.token.kind);
    try std.testing.expectEqualStrings("\"\"", result.token.lexeme(lexer.source_text));
}

test "scan string with escaped quote" {
    var lexer = Lexer.init(.{ .value = 1 }, "\"hello \\\"world\\\"\"");
    const result = lexer.nextToken();

    try std.testing.expectEqual(TokenKind.string, result.token.kind);
    try std.testing.expectEqualStrings(
        "\"hello \\\"world\\\"\"",
        result.token.lexeme(lexer.source_text),
    );
}

test "scan string with escaped backslash" {
    var lexer = Lexer.init(.{ .value = 1 }, "\"\\\\\"");
    const result = lexer.nextToken();

    try std.testing.expectEqual(TokenKind.string, result.token.kind);
    try std.testing.expectEqualStrings("\"\\\\\"", result.token.lexeme(lexer.source_text));
}

test "scan character literal" {
    var lexer = Lexer.init(.{ .value = 1 }, "'a'");
    const result = lexer.nextToken();

    try std.testing.expectEqual(TokenKind.character, result.token.kind);
    try std.testing.expectEqualStrings("'a'", result.token.lexeme(lexer.source_text));
}

test "scan escaped character literal" {
    var lexer = Lexer.init(.{ .value = 1 }, "'\\n'");
    const result = lexer.nextToken();

    try std.testing.expectEqual(TokenKind.character, result.token.kind);
    try std.testing.expectEqualStrings("'\\n'", result.token.lexeme(lexer.source_text));
}

test "reject empty character literal" {
    var lexer = Lexer.init(.{ .value = 1 }, "''");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "reject multiple characters in character literal" {
    var lexer = Lexer.init(.{ .value = 1 }, "'ab'");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "reject unterminated string literal" {
    var lexer = Lexer.init(.{ .value = 1 }, "\"hello");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "reject unterminated character literal" {
    var lexer = Lexer.init(.{ .value = 1 }, "'a");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "scan string containing UTF-8 characters" {
    var lexer = Lexer.init(.{ .value = 1 }, "\"café 🚀\"");
    const result = lexer.nextToken();

    try std.testing.expectEqual(TokenKind.string, result.token.kind);
    try std.testing.expectEqualStrings(
        "\"café 🚀\"",
        result.token.lexeme(lexer.source_text),
    );
}

test "scan two-byte UTF-8 character literal" {
    var lexer = Lexer.init(.{ .value = 1 }, "'é'");
    const result = lexer.nextToken();

    try std.testing.expectEqual(TokenKind.character, result.token.kind);
}

test "scan four-byte UTF-8 character literal" {
    var lexer = Lexer.init(.{ .value = 1 }, "'🚀'");
    const result = lexer.nextToken();

    try std.testing.expectEqual(TokenKind.character, result.token.kind);
}

test "reject invalid UTF-8 in string" {
    var lexer = Lexer.init(.{ .value = 1 }, "\"\xff\"");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "reject incomplete UTF-8 in string" {
    var lexer = Lexer.init(.{ .value = 1 }, "\"\xc3");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "reject invalid UTF-8 in character literal" {
    var lexer = Lexer.init(.{ .value = 1 }, "'\xff'");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

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
            return self.scanNumber();
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

    /// Scans a numeric literal.
    fn scanNumber(self: *Lexer) TokenResult {
        const start = self.position;

        if (self.startsWith("0x") or self.startsWith("0X")) {
            return self.scanRadixInteger(start, 16);
        }

        if (self.startsWith("0b") or self.startsWith("0B")) {
            return self.scanRadixInteger(start, 2);
        }

        return self.scanDecimalNumber(start);
    }

    /// Scans a hexadecimal or binary integer.
    fn scanRadixInteger(self: *Lexer, start: usize, radix: u8) TokenResult {
        self.position += 2;
        const digits_start = self.position;

        while (!self.isAtEnd() and
            (self.isRadixDigit(self.source_text[self.position], radix) or
                self.source_text[self.position] == '_'))
        {
            self.position += 1;
        }

        if (self.position == digits_start) {
            return .{ .diagnostic = self.makeDiagnostic(
                "Expected digits after numeric prefix",
                start,
                self.position,
            ) };
        }

        if (self.source_text[self.position - 1] == '_') {
            return .{ .diagnostic = self.makeDiagnostic(
                "Numeric literal cannot end with a separator",
                start,
                self.position,
            ) };
        }

        if (self.validateNumericSeparators(digits_start)) |diagnostic| {
            return .{ .diagnostic = diagnostic };
        }

        if (!self.isAtEnd() and std.ascii.isAlphanumeric(self.source_text[self.position])) {
            return .{ .diagnostic = self.makeDiagnostic(
                "Invalid digit in numeric literal",
                self.position,
                self.position + 1,
            ) };
        }

        const kind: TokenKind = switch (radix) {
            2 => .binary_integer,
            16 => .hex_integer,
            else => unreachable,
        };

        return .{ .token = self.makeToken(kind, start, self.position) };
    }

    /// Scans a decimal integer or floating-point literal.
    fn scanDecimalNumber(self: *Lexer, start: usize) TokenResult {
        self.scanDecimalDigits();

        if (self.validateDecimalDigits(start)) |diagnostic| {
            return .{ .diagnostic = diagnostic };
        }

        var kind: TokenKind = .integer;

        if (!self.isAtEnd() and self.source_text[self.position] == '.') {
            const dot_position = self.position;
            self.position += 1;

            if (self.isAtEnd() or !isDigit(self.source_text[self.position])) {
                return .{ .diagnostic = self.makeDiagnostic(
                    "Expected digit after decimal point",
                    dot_position,
                    self.position,
                ) };
            }

            kind = .float;
            self.scanDecimalDigits();

            if (self.validateDecimalDigits(start)) |diagnostic| {
                return .{ .diagnostic = diagnostic };
            }
        }

        if (!self.isAtEnd() and
            (self.source_text[self.position] == 'e' or self.source_text[self.position] == 'E'))
        {
            kind = .exponent_float;
            self.position += 1;

            if (!self.isAtEnd() and
                (self.source_text[self.position] == '+' or self.source_text[self.position] == '-'))
            {
                self.position += 1;
            }

            const exponent_start = self.position;
            self.scanDecimalDigits();

            if (self.position == exponent_start) {
                return .{ .diagnostic = self.makeDiagnostic(
                    "Expected exponent digits",
                    exponent_start,
                    self.position,
                ) };
            }

            if (self.validateDecimalDigits(exponent_start)) |diagnostic| {
                return .{ .diagnostic = diagnostic };
            }
        }

        return .{ .token = self.makeToken(kind, start, self.position) };
    }

    /// Consumes decimal digits and separators.
    fn scanDecimalDigits(self: *Lexer) void {
        while (!self.isAtEnd() and
            (isDigit(self.source_text[self.position]) or self.source_text[self.position] == '_'))
        {
            self.position += 1;
        }
    }

    /// Validates separators in a decimal digit sequence.
    fn validateDecimalDigits(self: *Lexer, start: usize) ?Diagnostic {
        if (self.position > start and self.source_text[self.position - 1] == '_') {
            return self.makeDiagnostic(
                "Numeric literal cannot end with a separator",
                start,
                self.position,
            );
        }

        return self.validateNumericSeparators(start);
    }

    /// Validates that separators occur only between valid digits.
    fn validateNumericSeparators(self: *Lexer, start: usize) ?Diagnostic {
        var i = start;

        while (i < self.position) : (i += 1) {
            if (self.source_text[i] != '_') continue;

            if (i == start or i + 1 == self.position or
                !self.isNumericDigit(self.source_text[i - 1]) or
                !self.isNumericDigit(self.source_text[i + 1]))
            {
                return self.makeDiagnostic(
                    "Invalid numeric separator",
                    i,
                    i + 1,
                );
            }
        }

        return null;
    }

    fn isNumericDigit(_: *Lexer, char: u8) bool {
        return isDigit(char) or isHexDigit(char);
    }

    fn isRadixDigit(self: *Lexer, char: u8, radix: u8) bool {
        _ = self;
        return switch (radix) {
            2 => char == '0' or char == '1',
            16 => isHexDigit(char),
            else => false,
        };
    }

    fn startsWith(self: *Lexer, prefix: []const u8) bool {
        return std.mem.startsWith(u8, self.source_text[self.position..], prefix);
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
        self.position += 1;

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

        var valid = true;

        while (!self.isAtEnd() and self.source_text[self.position] != '\'' and
            self.source_text[self.position] != '\n' and
            self.source_text[self.position] != '\r')
        {
            valid = false;

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
        }

        if (self.isAtEnd() or self.source_text[self.position] != '\'') {
            return .{ .diagnostic = self.makeDiagnostic(
                "Expected closing quote after character",
                start,
                self.position,
            ) };
        }

        self.position += 1;

        if (!valid) {
            return .{ .diagnostic = self.makeDiagnostic(
                "Character literal must contain exactly one character",
                start,
                self.position,
            ) };
        }

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
            'u' => return self.scanUnicodeEscape(start),
            else => return self.makeDiagnostic(
                "Invalid escape sequence",
                start,
                self.position,
            ),
        }
    }

    /// Consumes and validates a Unicode escape in the form \u{...}.
    fn scanUnicodeEscape(self: *Lexer, start: usize) ?Diagnostic {
        if (self.isAtEnd() or self.source_text[self.position] != '{') {
            return self.makeDiagnostic("Expected '{' after '\\u'", start, self.position);
        }

        self.position += 1;

        var value: u32 = 0;
        var digit_count: usize = 0;
        var too_many_digits = false;

        while (!self.isAtEnd() and isHexDigit(self.source_text[self.position])) {
            if (digit_count < 6) {
                value = value * 16 + hexValue(self.source_text[self.position]);
            } else {
                too_many_digits = true;
            }

            digit_count += 1;
            self.position += 1;
        }

        if (digit_count == 0) {
            return self.makeDiagnostic("Expected hexadecimal digits in Unicode escape", start, self.position);
        }

        if (self.isAtEnd() or self.source_text[self.position] != '}') {
            return self.makeDiagnostic("Expected '}' after Unicode escape", start, self.position);
        }

        self.position += 1;

        if (too_many_digits or value > 0x10FFFF or
            (value >= 0xD800 and value <= 0xDFFF))
        {
            return self.makeDiagnostic("Invalid Unicode code point", start, self.position);
        }

        return null;
    }

    /// Returns whether a byte is an ASCII hexadecimal digit.
    fn isHexDigit(char: u8) bool {
        return isDigit(char) or
            (char >= 'a' and char <= 'f') or
            (char >= 'A' and char <= 'F');
    }

    /// Returns the numeric value of an ASCII hexadecimal digit.
    fn hexValue(char: u8) u32 {
        return switch (char) {
            '0'...'9' => char - '0',
            'a'...'f' => char - 'a' + 10,
            'A'...'F' => char - 'A' + 10,
            else => unreachable,
        };
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

test "integer literal with digit separators" {
    const source_text = "1_000";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .token);
    try std.testing.expectEqual(TokenKind.integer, result.token.kind);
    try std.testing.expectEqualStrings("1_000", result.token.lexeme(source_text));
}

test "integer literal with multiple digit separators" {
    const source_text = "1_000_000";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .token);
    try std.testing.expectEqual(TokenKind.integer, result.token.kind);
    try std.testing.expectEqualStrings("1_000_000", result.token.lexeme(source_text));
}

test "floating-point literal with digit separators" {
    const source_text = "1_234.56_78";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .token);
    try std.testing.expectEqual(TokenKind.float, result.token.kind);
    try std.testing.expectEqualStrings("1_234.56_78", result.token.lexeme(source_text));
}

test "numeric literal with consecutive separators is invalid" {
    const source_text = "1__000";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings("Invalid numeric separator", result.diagnostic.message);
}

test "numeric literal cannot start a fractional part with a separator" {
    const source_text = "1._000";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Expected digit after decimal point",
        result.diagnostic.message,
    );
}

test "numeric literal cannot end with a decimal point" {
    const source_text = "12.";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Expected digit after decimal point",
        result.diagnostic.message,
    );
}

test "integer literal cannot end with a separator" {
    const source_text = "100_";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Numeric literal cannot end with a separator",
        result.diagnostic.message,
    );
}

test "floating-point literal cannot end with a separator" {
    const source_text = "12.5_";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Numeric literal cannot end with a separator",
        result.diagnostic.message,
    );
}

test "string literal with Unicode escape" {
    const source_text = "\"\\u{00E9}\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .token);
    try std.testing.expectEqual(TokenKind.string, result.token.kind);
    try std.testing.expectEqualStrings(source_text, result.token.lexeme(source_text));
}

test "string literal with four-byte Unicode escape" {
    const source_text = "\"\\u{1F680}\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .token);
    try std.testing.expectEqual(TokenKind.string, result.token.kind);
}

test "character literal with Unicode escape" {
    const source_text = "'\\u{00E9}'";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .token);
    try std.testing.expectEqual(TokenKind.character, result.token.kind);
}

test "character literal with four-byte Unicode escape" {
    const source_text = "'\\u{1F680}'";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .token);
    try std.testing.expectEqual(TokenKind.character, result.token.kind);
}

test "Unicode escape accepts uppercase hexadecimal digits" {
    const source_text = "\"\\u{1F4A9}\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .token);
}

test "Unicode escape accepts one hexadecimal digit" {
    const source_text = "\"\\u{A}\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .token);
}

test "Unicode escape rejects missing opening brace" {
    const source_text = "\"\\u1234\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Expected '{' after '\\u'",
        result.diagnostic.message,
    );
}

test "Unicode escape rejects empty braces" {
    const source_text = "\"\\u{}\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Expected hexadecimal digits in Unicode escape",
        result.diagnostic.message,
    );
}

test "Unicode escape rejects missing closing brace" {
    const source_text = "\"\\u{1234\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Expected '}' after Unicode escape",
        result.diagnostic.message,
    );
}

test "Unicode escape rejects non-hexadecimal digits" {
    const source_text = "\"\\u{12G4}\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Expected '}' after Unicode escape",
        result.diagnostic.message,
    );
}

test "Unicode escape rejects more than six hexadecimal digits" {
    const source_text = "\"\\u{1234567}\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Invalid Unicode code point",
        result.diagnostic.message,
    );
}

test "Unicode escape rejects code points above Unicode range" {
    const source_text = "\"\\u{110000}\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Invalid Unicode code point",
        result.diagnostic.message,
    );
}

test "Unicode escape rejects surrogate code points" {
    const source_text = "\"\\u{D800}\"";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Invalid Unicode code point",
        result.diagnostic.message,
    );
}

test "character literal with multiple characters reports one diagnostic and recovers" {
    const source_text = "'ab' foo";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqualStrings(
        "Character literal must contain exactly one character",
        result.diagnostic.message,
    );
    try std.testing.expectEqual(@as(usize, 0), result.diagnostic.span.start);
    try std.testing.expectEqual(@as(usize, 4), result.diagnostic.span.end);

    const next = lexer.nextToken();

    try std.testing.expect(next == .token);
    try std.testing.expectEqual(TokenKind.identifier, next.token.kind);
    try std.testing.expectEqualStrings("foo", next.token.lexeme(source_text));
}

test "trailing decimal point diagnostic span" {
    const source_text = "12.";
    var lexer = Lexer.init(.{ .value = 1 }, source_text);

    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqual(@as(usize, 2), result.diagnostic.span.start);
    try std.testing.expectEqual(@as(usize, 3), result.diagnostic.span.end);
}

test "lexes mixed source input" {
    const source_text =
        \\public record Person {
        \\    name: String, // person's name
        \\    age: i32 = 1_000;
        \\    score: f64 = 98.5;
        \\    active: bool = true;
        \\    /// Documentation comment
        \\}
    ;

    const ExpectedToken = struct {
        kind: TokenKind,
        lexeme: []const u8,
    };

    const expected = [_]ExpectedToken{
        .{ .kind = .keyword_public, .lexeme = "public" },
        .{ .kind = .keyword_record, .lexeme = "record" },
        .{ .kind = .identifier, .lexeme = "Person" },
        .{ .kind = .left_brace, .lexeme = "{" },
        .{ .kind = .identifier, .lexeme = "name" },
        .{ .kind = .colon, .lexeme = ":" },
        .{ .kind = .identifier, .lexeme = "String" },
        .{ .kind = .comma, .lexeme = "," },
        .{ .kind = .identifier, .lexeme = "age" },
        .{ .kind = .colon, .lexeme = ":" },
        .{ .kind = .identifier, .lexeme = "i32" },
        .{ .kind = .equal, .lexeme = "=" },
        .{ .kind = .integer, .lexeme = "1_000" },
        .{ .kind = .semicolon, .lexeme = ";" },
        .{ .kind = .identifier, .lexeme = "score" },
        .{ .kind = .colon, .lexeme = ":" },
        .{ .kind = .identifier, .lexeme = "f64" },
        .{ .kind = .equal, .lexeme = "=" },
        .{ .kind = .float, .lexeme = "98.5" },
        .{ .kind = .semicolon, .lexeme = ";" },
        .{ .kind = .identifier, .lexeme = "active" },
        .{ .kind = .colon, .lexeme = ":" },
        .{ .kind = .identifier, .lexeme = "bool" },
        .{ .kind = .equal, .lexeme = "=" },
        .{ .kind = .identifier, .lexeme = "true" },
        .{ .kind = .semicolon, .lexeme = ";" },
        .{ .kind = .doc_comment, .lexeme = "/// Documentation comment" },
        .{ .kind = .right_brace, .lexeme = "}" },
        .{ .kind = .eof, .lexeme = "" },
    };

    var lexer = Lexer.init(.{ .value = 1 }, source_text);
    var position: usize = 0;

    for (expected) |expected_token| {
        const result = lexer.nextToken();

        try std.testing.expect(result == .token);
        try std.testing.expectEqual(expected_token.kind, result.token.kind);
        try std.testing.expectEqualStrings(
            expected_token.lexeme,
            result.token.lexeme(source_text),
        );

        if (expected_token.kind == .eof) {
            try std.testing.expectEqual(position, result.token.span.start);
            try std.testing.expectEqual(position, result.token.span.end);
        } else {
            const offset = std.mem.indexOfPos(
                u8,
                source_text,
                position,
                expected_token.lexeme,
            ) orelse return error.ExpectedTokenNotFound;

            try std.testing.expectEqual(offset, result.token.span.start);
            try std.testing.expectEqual(
                offset + expected_token.lexeme.len,
                result.token.span.end,
            );

            position = result.token.span.end;
        }
    }
}

test "lexes hexadecimal integers" {
    const cases = [_][]const u8{
        "0x0",
        "0xFF",
        "0XCAFE",
        "0xCA_FE",
        "0x1_000",
    };

    for (cases) |source_text| {
        var lexer = Lexer.init(.{ .value = 1 }, source_text);
        const result = lexer.nextToken();

        try std.testing.expect(result == .token);
        try std.testing.expectEqual(TokenKind.hex_integer, result.token.kind);
        try std.testing.expectEqualStrings(source_text, result.token.lexeme(source_text));
    }
}

test "lexes binary integers" {
    const cases = [_][]const u8{
        "0b0",
        "0b1",
        "0b1010",
        "0B1101",
        "0b10_10",
        "0b1_000_000",
    };

    for (cases) |source_text| {
        var lexer = Lexer.init(.{ .value = 1 }, source_text);
        const result = lexer.nextToken();

        try std.testing.expect(result == .token);
        try std.testing.expectEqual(TokenKind.binary_integer, result.token.kind);
        try std.testing.expectEqualStrings(source_text, result.token.lexeme(source_text));
    }
}

test "lexes exponent floating-point literals" {
    const cases = [_][]const u8{
        "1e10",
        "1E10",
        "1e+10",
        "1e-10",
        "1.5e-3",
        "2E+4",
        "1_000e2",
        "1.5_0e2",
    };

    for (cases) |source_text| {
        var lexer = Lexer.init(.{ .value = 1 }, source_text);
        const result = lexer.nextToken();

        try std.testing.expect(result == .token);
        try std.testing.expectEqual(TokenKind.exponent_float, result.token.kind);
        try std.testing.expectEqualStrings(source_text, result.token.lexeme(source_text));
    }
}

test "rejects malformed hexadecimal integers" {
    const cases = [_][]const u8{
        "0x",
        "0x_",
        "0xG",
        "0x1G",
        "0xFF_",
        "0x_FF",
    };

    for (cases) |source_text| {
        var lexer = Lexer.init(.{ .value = 1 }, source_text);
        try std.testing.expect(lexer.nextToken() == .diagnostic);
    }
}

test "rejects malformed binary integers" {
    const cases = [_][]const u8{
        "0b",
        "0b_",
        "0b2",
        "0b102",
        "0b10_",
        "0b_10",
    };

    for (cases) |source_text| {
        var lexer = Lexer.init(.{ .value = 1 }, source_text);
        try std.testing.expect(lexer.nextToken() == .diagnostic);
    }
}

test "rejects malformed exponents" {
    const cases = [_][]const u8{
        "1e",
        "1e+",
        "1e-",
        "1e_",
        "1e+_2",
        "1e2_",
    };

    for (cases) |source_text| {
        var lexer = Lexer.init(.{ .value = 1 }, source_text);
        try std.testing.expect(lexer.nextToken() == .diagnostic);
    }
}

test "reject unknown string escape" {
    var lexer = Lexer.init(.{ .value = 1 }, "\"hello\\q\"");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "reject trailing string escape" {
    var lexer = Lexer.init(.{ .value = 1 }, "\"hello\\");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "reject unknown character escape" {
    var lexer = Lexer.init(.{ .value = 1 }, "'\\q'");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "reject trailing character escape" {
    var lexer = Lexer.init(.{ .value = 1 }, "'\\");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "reject malformed Unicode escape in string" {
    var lexer = Lexer.init(.{ .value = 1 }, "\"\\u{}\"");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

test "reject malformed Unicode escape in character literal" {
    var lexer = Lexer.init(.{ .value = 1 }, "'\\u{}'");
    const result = lexer.nextToken();

    try std.testing.expect(result == .diagnostic);
}

const std = @import("std");

const source_module = @import("../source/source.zig");
const Source = source_module.Source;

const span_module = @import("../source/span.zig");
const Span = span_module.Span;

const token_module = @import("../lexer/token.zig");
const Token = token_module.Token;
const TokenKind = token_module.TokenKind;

const expression_module = @import("expression.zig");
const Expression = expression_module.Expression;
const ExpressionKind = expression_module.ExpressionKind;

const operation_module = @import("operations.zig");
const BinaryOperation = operation_module.BinaryOperation;
const UnaryOperation = operation_module.UnaryOperation;

const diagnostic_module = @import("../diagnostics/diagnostic.zig");
const Diagnostic = diagnostic_module.Diagnostic;
const Severity = diagnostic_module.Severity;

pub const ParseResult = union(enum) {
    expression: *const Expression,
    diagnostic: Diagnostic,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    source: *const Source,
    tokens: []const Token,
    cursor: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source: *const Source, tokens: []const Token) Self {
        return .{
            .allocator = allocator,
            .source = source,
            .tokens = tokens,
            .cursor = 0,
        };
    }

    pub fn parse(self: *Self) !ParseResult {
        const expr = self.parseExpression() catch |err| switch (err) {
            error.ExpectedExpression => {
                return .{
                    .diagnostic = try self.makeExpectedExpressionDiagnostic(),
                };
            },
            error.OutOfMemory => return error.OutOfMemory,
        };

        return .{ .expression = expr };
    }

    fn parseExpression(self: *Self) !*const Expression {
        return try self.parseEquality();
    }

    fn parseEquality(self: *Self) !*const Expression {
        var expr = try self.parseComparison();
        while (self.match(&[_]TokenKind{ .bang_equal, .equal_equal })) {
            const operator_token = self.previous();
            const op = BinaryOperation.fromTokenKind(operator_token.kind);
            const right = try self.parseComparison();
            const span = expr.span.merge(operator_token.span).merge(right.span);
            const ptr = try self.allocator.create(Expression);
            ptr.* = Expression{
                .kind = .{
                    .binary = .{
                        .lhs = expr,
                        .op = op,
                        .rhs = right,
                    },
                },
                .span = span,
            };
            expr = ptr;
        }

        return expr;
    }

    fn parseComparison(self: *Self) !*const Expression {
        var expr = try self.parseTerm();
        while (self.match(&[_]TokenKind{ .greater, .greater_equal, .less, .less_equal })) {
            const operator_token = self.previous();
            const op = BinaryOperation.fromTokenKind(operator_token.kind);
            const right = try self.parseTerm();
            const span = expr.span.merge(operator_token.span).merge(right.span);
            const ptr = try self.allocator.create(Expression);
            ptr.* = Expression{
                .kind = .{
                    .binary = .{
                        .lhs = expr,
                        .op = op,
                        .rhs = right,
                    },
                },
                .span = span,
            };
            expr = ptr;
        }

        return expr;
    }

    fn parseTerm(self: *Self) !*const Expression {
        var expr = try self.parseFactor();
        while (self.match(&[_]TokenKind{ .minus, .plus })) {
            const operator_token = self.previous();
            const op = BinaryOperation.fromTokenKind(operator_token.kind);
            const right = try self.parseFactor();
            const span = expr.span.merge(operator_token.span).merge(right.span);
            const ptr = try self.allocator.create(Expression);
            ptr.* = Expression{
                .kind = .{
                    .binary = .{
                        .lhs = expr,
                        .op = op,
                        .rhs = right,
                    },
                },
                .span = span,
            };
            expr = ptr;
        }

        return expr;
    }

    fn parseFactor(self: *Self) !*const Expression {
        var expr = try self.parseUnary();
        while (self.match(&[_]TokenKind{ .slash, .star })) {
            const operator_token = self.previous();
            const op = BinaryOperation.fromTokenKind(operator_token.kind);
            const right = try self.parseUnary();
            const span = expr.span.merge(operator_token.span).merge(right.span);
            const ptr = try self.allocator.create(Expression);
            ptr.* = Expression{
                .kind = .{
                    .binary = .{
                        .lhs = expr,
                        .op = op,
                        .rhs = right,
                    },
                },
                .span = span,
            };
            expr = ptr;
        }

        return expr;
    }

    fn parseUnary(self: *Self) !*const Expression {
        if (self.match(&[_]TokenKind{ .bang, .minus })) {
            const operator_token = self.previous();
            const op = UnaryOperation.fromTokenKind(operator_token.kind);
            const right = try self.parseUnary();
            const span = operator_token.span.merge(right.span);
            const ptr = try self.allocator.create(Expression);
            ptr.* = Expression{
                .kind = .{
                    .unary = .{
                        .op = op,
                        .operand = right,
                    },
                },
                .span = span,
            };

            return ptr;
        }

        return self.parsePrimary();
    }

    fn parsePrimary(self: *Self) !*const Expression {
        if (self.match(&[_]TokenKind{.keyword_false})) {
            const prev = self.previous();
            const ptr = try self.allocator.create(Expression);
            ptr.* = Expression{
                .kind = .{ .boolean_literal = false },
                .span = prev.span,
            };
            return ptr;
        }

        if (self.match(&[_]TokenKind{.keyword_true})) {
            const prev = self.previous();
            const ptr = try self.allocator.create(Expression);
            ptr.* = Expression{
                .kind = .{ .boolean_literal = true },
                .span = prev.span,
            };
            return ptr;
        }

        return error.ExpectedExpression;
        // TODO: handle other literal cases.
        // integer
        // float
        // hex
        // binary
        // scientific notation
        // character literals
        // string literals
        //
        // groupings
        // nil?

        // CI examples:
        // if (match(NIL)) return new Expr.Literal(null);

        // if (match(NUMBER, STRING)) {
        //   return new Expr.Literal(previous().literal);
        // }

        // if (match(LEFT_PAREN)) {
        //   Expr expr = expression();
        //   consume(RIGHT_PAREN, "Expect ')' after expression.");
        //   return new Expr.Grouping(expr);
        // }
    }

    fn match(self: *Self, types: []const TokenKind) bool {
        for (types) |token_type| {
            if (self.check(token_type)) {
                _ = self.advance();
                return true;
            }
        }

        return false;
    }

    fn check(self: *Self, token_type: TokenKind) bool {
        if (self.isAtEnd()) {
            return false;
        }

        return self.peek().kind == token_type;
    }

    fn advance(self: *Self) Token {
        if (!self.isAtEnd()) {
            self.cursor += 1;
        }

        return self.previous();
    }

    fn isAtEnd(self: *Self) bool {
        return self.peek().kind == .eof;
    }

    fn peek(self: *Self) Token {
        return self.tokens[self.cursor];
    }

    fn previous(self: *Self) Token {
        return self.tokens[self.cursor - 1];
    }

    fn makeExpectedExpressionDiagnostic(self: *Self) !Diagnostic {
        const token = self.peek();

        return Diagnostic{
            .severity = .err,
            .message = "Expected expression.",
            .span = token.span,
        };
    }
};

const lexer_module = @import("../lexer/lexer.zig");
const Lexer = lexer_module.Lexer;
const TokenResult = lexer_module.TokenResult;

fn makeSource(text: []const u8) Source {
    return .{
        .id = .{ .value = 1 },
        .path = "",
        .text = text,
    };
}

fn makeTokens(allocator: std.mem.Allocator, text: []const u8, capacity: usize) !std.ArrayList(Token) {
    var tokens = try std.ArrayList(Token).initCapacity(allocator, capacity);
    const source = makeSource(text);
    var lexer = Lexer.init(&source);

    token_loop: while (true) {
        const result = lexer.nextToken();
        switch (result) {
            .diagnostic => return error.UnexpectedDiagnostic,
            .token => |tok| {
                try tokens.append(allocator, tok);
                if (tok.kind == .eof) {
                    break :token_loop;
                }
            },
        }
    }

    return tokens;
}

test "parse boolean literal true" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const source_code = "true";
    const source = makeSource(source_code);
    var tokens = try makeTokens(allocator, source_code, 2);
    defer tokens.deinit(allocator);

    var parser = Parser.init(
        allocator,
        &source,
        tokens.items,
    );

    switch (try parser.parse()) {
        .expression => |expr| {
            try std.testing.expectEqual(
                ExpressionKind{ .boolean_literal = true },
                expr.kind,
            );
        },
        .diagnostic => {
            return error.UnexpectedDiagnostic;
        },
    }
}

test "parse boolean literal false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const source_code = "false";
    const source = makeSource(source_code);
    var tokens = try makeTokens(allocator, source_code, 2);
    defer tokens.deinit(allocator);

    var parser = Parser.init(
        allocator,
        &source,
        tokens.items,
    );

    switch (try parser.parse()) {
        .expression => |expr| {
            try std.testing.expectEqual(
                ExpressionKind{ .boolean_literal = false },
                expr.kind,
            );
        },
        .diagnostic => {
            return error.UnexpectedDiagnostic;
        },
    }
}

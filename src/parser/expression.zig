const std = @import("std");
const span_module = @import("../source/span.zig");
const Span = span_module.Span;

const operations_module = @import("operations.zig");
const BinaryOperation = operations_module.BinaryOperation;
const UnaryOperation = operations_module.UnaryOperation;

pub const ExpressionKind = union(enum) {
    binary: struct {
        lhs: *const Expression,
        op: BinaryOperation,
        rhs: *const Expression,
    },
    boolean_literal: bool,
    float_literal: f64,
    grouping: *const Expression,
    integer_literal: i64,
    string_literal: []const u8,
    unary: struct {
        op: UnaryOperation,
        operand: *const Expression,
    },
};

pub const Expression = struct {
    kind: ExpressionKind,
    span: Span,
};

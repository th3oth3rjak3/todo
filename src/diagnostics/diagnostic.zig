const source = @import("../source/span.zig");
const Span = source.Span;

/// The severity level of a diagnostic.
pub const Severity = enum {
    /// An error that prevents successful compilation.
    err,

    /// A warning about potentially problematic source code.
    warning,

    /// Additional informational context about a diagnostic.
    note,
};

/// Describes an issue found while processing source code.
pub const Diagnostic = struct {
    /// The severity of the diagnostic.
    severity: Severity,

    /// A human-readable description of the issue.
    message: []const u8,

    /// The location in source code associated with the diagnostic.
    span: Span,

    const Self = @This();

    /// Creates an error diagnostic.
    pub fn err(message: []const u8, span: Span) Self {
        return .{
            .severity = .err,
            .message = message,
            .span = span,
        };
    }

    /// Creates a warning diagnostic.
    pub fn warn(message: []const u8, span: Span) Self {
        return .{
            .severity = .warning,
            .message = message,
            .span = span,
        };
    }

    /// Creates an informational diagnostic note.
    pub fn note(message: []const u8, span: Span) Self {
        return .{
            .severity = .note,
            .message = message,
            .span = span,
        };
    }
};

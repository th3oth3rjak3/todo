const source = @import("../source/span.zig");

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
    span: source.Span,
};

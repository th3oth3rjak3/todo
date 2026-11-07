const std = @import("std");
const source = @import("source.zig");

/// Identifies a range of bytes within a source file.
pub const Span = struct {
    /// The source file containing this span.
    source: source.SourceId,

    /// The inclusive starting byte offset within the source file.
    start: usize,

    /// The exclusive ending byte offset within the source file.
    ///
    /// A span with equal start and end offsets represents an empty range.
    end: usize,

    /// Returns a span covering both spans.
    ///
    /// Both spans must refer to the same source file.
    pub fn merge(self: Span, other: Span) Span {
        std.debug.assert(self.source.value == other.source.value);

        return .{
            .source = self.source,
            .start = @min(self.start, other.start),
            .end = @max(self.end, other.end),
        };
    }
};

test "merge combines two spans" {
    const source_id = source.SourceId{ .value = 1 };

    const first = Span{
        .source = source_id,
        .start = 10,
        .end = 20,
    };

    const second = Span{
        .source = source_id,
        .start = 4,
        .end = 25,
    };

    const merged = first.merge(second);

    try std.testing.expectEqual(source_id.value, merged.source.value);
    try std.testing.expectEqual(@as(usize, 4), merged.start);
    try std.testing.expectEqual(@as(usize, 25), merged.end);
}

const SourceId = @import("source_manager.zig").SourceId;

pub const Span = struct {
    source_id: SourceId,
    start: usize,
    end: usize,
};

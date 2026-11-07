/// Identifies a source file managed by a SourceManager.
///
/// The ID is only valid for the lifetime of the SourceManager that created it.
pub const SourceId = struct {
    /// The numeric identifier assigned by the SourceManager.
    value: u32,
};

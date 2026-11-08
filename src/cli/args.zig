//! Application-owned CLI argument types.
//!
//! These types are independent of the argument-parsing library.

pub const app_name = "todo";
pub const app_version = "0.1.0";

pub const CliArgs = union(enum) {
    lex: LexArgs,
    help: HelpArgs,
    version: VersionArgs,
};

pub const LexArgs = struct {
    /// Path to the source file to lex.
    file: []const u8,
};

pub const HelpArgs = struct {
    /// Generated help text, ready for display.
    text: []const u8,
};

pub const VersionArgs = struct {
    /// Formatted version text, ready for display.
    text: []const u8,
};

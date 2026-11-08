//! CLI command dispatcher.
//!
//! Executes commands and presents application-level CLI responses.

const std = @import("std");

const args_module = @import("args.zig");
const CliArgs = args_module.CliArgs;

const lex_command = @import("../commands/lex.zig");

pub fn run(
    args: CliArgs,
    io: std.Io,
    allocator: std.mem.Allocator,
) !void {
    switch (args) {
        .lex => |lex_args| try lex_command.run(lex_args, io, allocator),
        .help => |help_args| {
            try std.Io.File.stdout().writeStreamingAll(io, help_args.text);
        },
        .version => |version_args| {
            try std.Io.File.stdout().writeStreamingAll(io, version_args.text);
        },
    }
}

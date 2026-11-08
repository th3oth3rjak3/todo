//! CLI argument parsing adapter backed by args.zig v0.0.9.
//!
//! Converts library-specific parse results into application-owned CLI types.

const std = @import("std");
const args_library = @import("args");

const args_module = @import("args.zig");
const CliArgs = args_module.CliArgs;

const LexArgs = args_module.LexArgs;
const HelpArgs = args_module.HelpArgs;
const VersionArgs = args_module.VersionArgs;

const lex_help = "Print the token stream for a source file";
const file_help = "Source file to lex";

pub fn parse(init: std.process.Init) !CliArgs {
    const allocator = init.arena.allocator();

    var parser = try args_library.ArgumentParser.init(allocator, .{
        .name = args_module.app_name,
        .version = args_module.app_version,
        .description = "The todo programming language toolchain.",
        .add_help = false,
        .add_version = false,
    });
    defer parser.deinit();

    // Register application-owned help and version options.
    try parser.addFlag("help", .{
        .short = 'h',
        .help = "Display help information",
    });

    try parser.addFlag("version", .{
        .help = "Display version information",
    });

    // Define the lex command's arguments.
    const lex_arguments = [_]args_library.ArgSpec{
        .{
            .name = "file",
            .positional = true,
            .help = file_help,
        },
        .{
            .name = "help",
            .short = 'h',
            .long = "help",
            .action = .store_true,
            .help = "Display help information",
        },
        .{
            .name = "version",
            .long = "version",
            .action = .store_true,
            .help = "Display version information",
        },
    };

    try parser.addSubcommand(.{
        .name = "lex",
        .help = lex_help,
        .args = &lex_arguments,
    });

    var result = try parser.parseProcess(init);
    defer result.deinit();

    if (result.getBool("help") orelse false) {
        return .{
            .help = .{
                .text = try parser.getHelp(),
            },
        };
    }

    if (result.getBool("version") orelse false) {
        return makeVersionArgs(allocator, parser.getVersion());
    }

    const subcommand = result.subcommand orelse {
        return .{
            .help = .{
                .text = try parser.getHelp(),
            },
        };
    };

    if (!std.mem.eql(u8, subcommand, "lex")) {
        return .{
            .help = .{
                .text = try parser.getHelp(),
            },
        };
    }

    const subcommand_args = result.subcommand_args orelse {
        return .{
            .help = .{
                .text = try makeLexHelp(allocator, &lex_arguments),
            },
        };
    };

    if (subcommand_args.getBool("help") orelse false) {
        return .{
            .help = .{
                .text = try makeLexHelp(allocator, &lex_arguments),
            },
        };
    }

    if (subcommand_args.getBool("version") orelse false) {
        return makeVersionArgs(allocator, parser.getVersion());
    }

    const file = subcommand_args.getString("file") orelse {
        return .{
            .help = .{
                .text = try makeLexHelp(allocator, &lex_arguments),
            },
        };
    };

    return .{
        .lex = LexArgs{
            .file = try allocator.dupe(u8, file),
        },
    };
}

fn makeVersionArgs(
    allocator: std.mem.Allocator,
    version: []const u8,
) !CliArgs {
    return .{
        .version = VersionArgs{
            .text = try std.fmt.allocPrint(
                allocator,
                "{s} {s}\n",
                .{ args_module.app_name, version },
            ),
        },
    };
}

fn makeLexHelp(
    allocator: std.mem.Allocator,
    arguments: []const args_library.ArgSpec,
) ![]const u8 {
    var parser = try args_library.ArgumentParser.init(allocator, .{
        .name = "todo lex",
        .description = lex_help,
        .version = args_module.app_version,
        .add_help = false,
        .add_version = false,
    });
    defer parser.deinit();

    for (arguments) |argument| {
        try parser.addArg(argument);
    }

    return try parser.getHelp();
}

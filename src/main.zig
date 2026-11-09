const std = @import("std");
const span = @import("source/span.zig");
const source = @import("source/source.zig");
const token = @import("lexer/token.zig");
const lexer = @import("lexer/lexer.zig");
const diagnostic_writer = @import("diagnostics/writer.zig");
const parser = @import("parser/parser.zig");

const args_parser = @import("cli/args_zig.zig");
const cli = @import("cli/cli.zig");
const lex_command = @import("commands/lex.zig");

pub fn main(init: std.process.Init) u8 {
    const args = args_parser.parse(init) catch return 1;
    cli.run(args, init.io, init.gpa) catch return 1;
    return 0;
}

comptime {
    std.testing.refAllDecls(span);
    std.testing.refAllDecls(source);
    std.testing.refAllDecls(token);
    std.testing.refAllDecls(lexer);
    std.testing.refAllDecls(diagnostic_writer);
    std.testing.refAllDecls(parser);
    std.testing.refAllDecls(lex_command);
}

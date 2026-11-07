const std = @import("std");
const span = @import("source/span.zig");
const source = @import("source/source.zig");
const token = @import("lexer/token.zig");
const lexer = @import("lexer/lexer.zig");

pub fn main(_: std.process.Init) void {
    std.debug.print("Hello, world!\n", .{});
}

comptime {
    std.testing.refAllDecls(span);
    std.testing.refAllDecls(source);
    std.testing.refAllDecls(token);
    std.testing.refAllDecls(lexer);
}

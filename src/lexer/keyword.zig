const token = @import("token.zig");

pub const Keyword = struct {
    lexeme: []const u8,
    kind: token.Kind,
};

pub const keywords = [_]Keyword{
    .{ .lexeme = "pub", .kind = .keyword_pub },
    .{ .lexeme = "struct", .kind = .keyword_struct },
};

const std = @import("std");
const source_manager = @import("source_manager.zig");

comptime {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(source_manager);
}

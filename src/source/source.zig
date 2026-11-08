const std = @import("std");

/// Identifies a source file managed by a SourceManager.
///
/// The ID is only valid for the lifetime of the SourceManager that created it.
pub const SourceId = struct {
    /// The numeric identifier assigned by the SourceManager.
    value: u32,
};

/// `Source` represents a single source code file.
pub const Source = struct {
    /// The id of this source.
    id: SourceId,
    /// The original source code file path.
    path: []const u8,
    /// The contents of the source code file.
    text: []const u8,
};

/// A type-erased interface for retrieving source files.
///
/// Consumers provide an implementation that resolves a `SourceId`
/// to a `Source`. The `DiagnosticWriter` uses this interface to retrieve
/// source code when rendering diagnostics, without depending on how the
/// consumer stores or manages source files.
pub const SourceProvider = struct {
    /// A pointer to the consumer's source provider implementation.
    ptr: *const anyopaque,

    /// A callback that retrieves a source file by its ID.
    getSourceFn: *const fn (ptr: *const anyopaque, id: SourceId) ?Source,

    /// Retrieves the source file associated with `id`.
    ///
    /// Returns `null` if the source file cannot be found.
    pub fn getSource(self: @This(), id: SourceId) ?Source {
        return self.getSourceFn(self.ptr, id);
    }
};

test "SourceProvider retrieves source files" {
    const TestProvider = struct {
        sources: std.AutoHashMap(SourceId, Source),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .sources = .init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.sources.deinit();
        }

        pub fn addSource(
            self: *@This(),
            id: SourceId,
            source: Source,
        ) !void {
            try self.sources.put(id, source);
        }

        pub fn sourceProvider(self: *const @This()) SourceProvider {
            return .{
                .ptr = self,
                .getSourceFn = getSource,
            };
        }

        fn getSource(ptr: *const anyopaque, id: SourceId) ?Source {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            return self.sources.get(id);
        }
    };

    var implementation = TestProvider.init(std.testing.allocator);
    defer implementation.deinit();

    const id: SourceId = .{ .value = 1 };

    try implementation.addSource(id, .{
        .id = id,
        .path = "test.zig",
        .text = "const answer = 42;",
    });

    const provider = implementation.sourceProvider();
    const result = provider.getSource(id);

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("test.zig", result.?.path);
    try std.testing.expectEqualStrings("const answer = 42;", result.?.text);
}

test "SourceProvider returns null for unknown source IDs" {
    const TestProvider = struct {
        fn getSource(_: *const anyopaque, _: SourceId) ?Source {
            return null;
        }
    };

    const implementation = TestProvider{};
    const provider = SourceProvider{
        .ptr = &implementation,
        .getSourceFn = TestProvider.getSource,
    };

    const result = provider.getSource(.{ .value = 999 });

    try std.testing.expectEqual(null, result);
}

test "SourceProvider retrieves the correct source by ID" {
    const TestProvider = struct {
        sources: [2]Source,

        fn getSource(ptr: *const anyopaque, id: SourceId) ?Source {
            const self: *const @This() = @ptrCast(@alignCast(ptr));

            return switch (id.value) {
                1 => self.sources[0],
                2 => self.sources[1],
                else => null,
            };
        }
    };

    const implementation = TestProvider{
        .sources = .{
            .{
                .id = .{ .value = 1 },
                .path = "first.zig",
                .text = "const first = 1;",
            },
            .{
                .id = .{ .value = 2 },
                .path = "second.zig",
                .text = "const second = 2;",
            },
        },
    };

    const provider = SourceProvider{
        .ptr = &implementation,
        .getSourceFn = TestProvider.getSource,
    };

    const first = provider.getSource(.{ .value = 1 }).?;
    const second = provider.getSource(.{ .value = 2 }).?;

    try std.testing.expectEqualStrings("first.zig", first.path);
    try std.testing.expectEqualStrings("const first = 1;", first.text);

    try std.testing.expectEqualStrings("second.zig", second.path);
    try std.testing.expectEqualStrings("const second = 2;", second.text);
}

test "SourceProvider supports different implementations" {
    const TestProvider = struct {
        source: Source,

        fn getSource(ptr: *const anyopaque, id: SourceId) ?Source {
            if (id.value != 1) return null;

            const self: *const @This() = @ptrCast(@alignCast(ptr));
            return self.source;
        }
    };

    const implementation = TestProvider{
        .source = .{
            .id = .{ .value = 1 },
            .path = "single.zig",
            .text = "const value = 42;",
        },
    };

    const provider = SourceProvider{
        .ptr = &implementation,
        .getSourceFn = TestProvider.getSource,
    };

    const result = provider.getSource(implementation.source.id);

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("single.zig", result.?.path);
    try std.testing.expectEqualStrings("const value = 42;", result.?.text);
}

test "SourceProvider supports different ID types" {
    const TestProvider = struct {
        fn getSource(_: *const anyopaque, id: SourceId) ?Source {
            if (id.value != 42) return null;

            return .{
                .id = id,
                .path = "test.zig",
                .text = "hello",
            };
        }
    };

    const implementation = TestProvider{};
    const provider = SourceProvider{
        .ptr = &implementation,
        .getSourceFn = TestProvider.getSource,
    };

    const result = provider.getSource(.{ .value = 42 });

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("test.zig", result.?.path);
}

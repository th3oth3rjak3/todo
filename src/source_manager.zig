const std = @import("std");

/// Identifies a source file managed by `SourceManager`.
pub const SourceId = struct {
    value: usize,

    /// Returns a source ID with the given value.
    pub fn init(value: usize) SourceId {
        return .{ .value = value };
    }
};

/// A source file registered with a `SourceManager`.
pub const SourceCodeFile = struct {
    /// The source file's ID.
    id: SourceId,
    /// The source file's name.
    name: []const u8,
    /// The source file's contents.
    contents: []const u8,

    /// Initializes a source file with the given ID, name, and contents.
    pub fn init(
        id: SourceId,
        name: []const u8,
        contents: []const u8,
    ) SourceCodeFile {
        return .{
            .id = id,
            .name = name,
            .contents = contents,
        };
    }
};

/// Stores source files and assigns each one a unique ID.
pub const SourceManager = struct {
    /// The allocator used for source data and storage.
    allocator: std.mem.Allocator,
    /// The source files registered with this manager.
    sources: std.ArrayList(SourceCodeFile),

    /// Initializes an empty source manager.
    pub fn init(allocator: std.mem.Allocator) SourceManager {
        return .{
            .allocator = allocator,
            .sources = .empty,
        };
    }

    /// Adds a source file and returns its ID.
    ///
    /// The source manager stores copies of `name` and `contents`.
    /// The caller retains ownership of the original slices.
    pub fn addSource(
        self: *SourceManager,
        name: []const u8,
        contents: []const u8,
    ) !SourceId {
        const owned_contents = try self.allocator.dupe(u8, contents);
        return self.addOwnedSource(name, owned_contents);
    }

    /// Registers a source file, taking ownership of `contents`.
    ///
    /// The source manager also stores its own copy of `name`.
    fn addOwnedSource(
        self: *SourceManager,
        name: []const u8,
        contents: []u8,
    ) !SourceId {
        errdefer self.allocator.free(contents);

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        const id = SourceId.init(self.sources.items.len);
        const file = SourceCodeFile.init(id, owned_name, contents);

        const pointer = try self.sources.addOne(self.allocator);
        pointer.* = file;

        return id;
    }

    /// Loads a source file from a directory and returns its ID.
    ///
    /// The source manager takes ownership of the file contents and a copy
    /// of the path.
    pub fn loadSource(
        self: *SourceManager,
        io: std.Io,
        dir: std.Io.Dir,
        path: []const u8,
    ) !SourceId {
        const contents = try dir.readFileAlloc(
            io,
            path,
            self.allocator,
            .unlimited,
        );

        return self.addOwnedSource(path, contents);
    }

    /// Releases all memory owned by the source manager.
    pub fn deinit(self: *SourceManager) void {
        for (self.sources.items) |source| {
            self.allocator.free(source.name);
            self.allocator.free(source.contents);
        }

        self.sources.deinit(self.allocator);
    }
};

test "SourceManager creates a new source" {
    const allocator = std.testing.allocator;

    var manager = SourceManager.init(allocator);
    defer manager.deinit();

    const temp_name = try allocator.dupe(u8, "test.todo");
    defer allocator.free(temp_name);

    const temp_contents = try allocator.dupe(u8, "var x = 1;");
    defer allocator.free(temp_contents);

    const id = try manager.addSource(temp_name, temp_contents);
    try std.testing.expectEqual(0, id.value);
    try std.testing.expectEqual(1, manager.sources.items.len);
}

test "SourceManager.addSource handles allocation failures" {
    for (0..3) |fail_index| {
        var failing_allocator = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{ .fail_index = fail_index },
        );

        var manager = SourceManager.init(failing_allocator.allocator());
        defer manager.deinit();

        try std.testing.expectError(
            error.OutOfMemory,
            manager.addSource("test.todo", "var x = 1;"),
        );

        try std.testing.expectEqual(0, manager.sources.items.len);
    }
}

test "SourceManager.addSource copies source name and contents" {
    const allocator = std.testing.allocator;

    var manager = SourceManager.init(allocator);
    defer manager.deinit();

    const name = try allocator.dupe(u8, "test.todo");
    defer allocator.free(name);

    const contents = try allocator.dupe(u8, "var x = 1;");
    defer allocator.free(contents);

    const id = try manager.addSource(name, contents);

    // Mutate the caller-owned buffers.
    @memset(name, 'x');
    @memset(contents, 'x');

    const source = manager.sources.items[id.value];

    try std.testing.expectEqualStrings("test.todo", source.name);
    try std.testing.expectEqualStrings("var x = 1;", source.contents);
}

test "SourceManager.addSource accepts empty slices" {
    const allocator = std.testing.allocator;

    var manager = SourceManager.init(allocator);
    defer manager.deinit();

    const id = try manager.addSource("", "");

    const source = manager.sources.items[id.value];
    try std.testing.expectEqualStrings("", source.name);
    try std.testing.expectEqualStrings("", source.contents);
}

test "SourceManager.addSource assigns distinct IDs" {
    const allocator = std.testing.allocator;

    var manager = SourceManager.init(allocator);
    defer manager.deinit();

    const first = try manager.addSource("first.todo", "var x = 1;");
    const second = try manager.addSource("second.todo", "var y = 2;");
    const third = try manager.addSource("third.todo", "var z = 3;");

    try std.testing.expectEqual(0, first.value);
    try std.testing.expectEqual(1, second.value);
    try std.testing.expectEqual(2, third.value);

    try std.testing.expectEqual(@as(usize, 3), manager.sources.items.len);
}

test "SourceManager.loadSource loads a file" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const expected_contents = "var x = 42;";

    try tmp_dir.dir.writeFile(io, .{
        .sub_path = "test.todo",
        .data = expected_contents,
    });

    var manager = SourceManager.init(allocator);
    defer manager.deinit();

    const id = try manager.loadSource(io, tmp_dir.dir, "test.todo");

    try std.testing.expectEqual(0, id.value);
    try std.testing.expectEqual(1, manager.sources.items.len);

    const source = manager.sources.items[id.value];

    try std.testing.expectEqualStrings("test.todo", source.name);
    try std.testing.expectEqualStrings(expected_contents, source.contents);
}

test "SourceManager.loadSource accepts empty files" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(io, .{
        .sub_path = "empty.todo",
        .data = "",
    });

    var manager = SourceManager.init(allocator);
    defer manager.deinit();

    const id = try manager.loadSource(io, tmp_dir.dir, "empty.todo");

    const source = manager.sources.items[id.value];

    try std.testing.expectEqual(0, id.value);
    try std.testing.expectEqualStrings("empty.todo", source.name);
    try std.testing.expectEqualStrings("", source.contents);
}

test "SourceManager.loadSource handles missing files" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var manager = SourceManager.init(allocator);
    defer manager.deinit();

    try std.testing.expectError(
        error.FileNotFound,
        manager.loadSource(io, tmp_dir.dir, "missing.todo"),
    );

    try std.testing.expectEqual(0, manager.sources.items.len);
}

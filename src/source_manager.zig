const std = @import("std");
const diag = @import("diagnostics");
const traits = @import("traits");
const Source = diag.Source;
const SourceProvider = diag.SourceProvider(usize);
const SourceId = diag.SourceId(usize);

/// A source file registered with a `SourceManager`.
/// `SourceManager` owns the heap data.
pub const SourceCodeFile = struct {
    /// The source file's ID.
    id: SourceId,

    /// The source file's relative path from the manager's root directory.
    relative_path: []const u8,

    /// The source file's contents.
    contents: []const u8,

    pub fn init(
        id: SourceId,
        relative_path: []const u8,
        contents: []const u8,
    ) SourceCodeFile {
        return .{
            .id = id,
            .relative_path = relative_path,
            .contents = contents,
        };
    }
};

/// Stores source files and assigns each one a unique ID.
pub const SourceManager = struct {
    allocator: std.mem.Allocator,
    root_path: []const u8,
    sources: std.ArrayList(SourceCodeFile),

    const Self = @This();

    /// Initializes a source manager with a root directory.
    pub fn init(
        allocator: std.mem.Allocator,
        root_path: []const u8,
    ) !Self {
        const owned_root_path = try allocator.dupe(u8, root_path);

        return .{
            .allocator = allocator,
            .root_path = owned_root_path,
            .sources = .empty,
        };
    }

    /// Loads a source file relative to the manager's root directory.
    pub fn loadSource(
        self: *Self,
        io: std.Io,
        relative_path: []const u8,
    ) !SourceId {
        var root_dir = try std.Io.Dir.openDirAbsolute(
            io,
            self.root_path,
            .{},
        );
        defer root_dir.close(io);

        const owned_contents = try root_dir.readFileAlloc(
            io,
            relative_path,
            self.allocator,
            .unlimited,
        );
        errdefer self.allocator.free(owned_contents);

        const owned_path = try self.allocator.dupe(u8, relative_path);
        errdefer self.allocator.free(owned_path);

        const id = SourceId.init(self.sources.items.len);

        const source = SourceCodeFile.init(
            id,
            owned_path,
            owned_contents,
        );

        const slot = try self.sources.addOne(self.allocator);
        slot.* = source;

        return id;
    }

    /// Returns a registered source file by ID.
    pub fn getSourceFile(
        self: *const Self,
        id: SourceId,
    ) ?SourceCodeFile {
        if (id.raw >= self.sources.items.len) return null;
        return self.sources.items[id.raw];
    }

    /// Construct a SourceProvider interface for this manager.
    pub fn sourceProvider(self: *const Self) SourceProvider {
        return .{ .ptr = self, .getSourceFn = getSource };
    }

    /// The source converter that's used to convert SourceCodeFile to Source
    /// for a diagnostic writer.
    const source_converter = traits.impl(traits.Convert(SourceCodeFile, Source), struct {
        pub fn convert(input: SourceCodeFile) Source {
            return .{
                .path = input.relative_path,
                .text = input.contents,
            };
        }
    });

    /// Get the source file for the trait implementation.
    fn getSource(self: *const anyopaque, id: SourceId) ?Source {
        const typed_self: *const Self = @ptrCast(@alignCast(self));
        const result = typed_self.getSourceFile(id);
        if (result == null) return null;
        return source_converter.convert(result.?);
    }

    /// Releases all memory owned by the source manager.
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.root_path);

        for (self.sources.items) |source| {
            self.allocator.free(source.relative_path);
            self.allocator.free(source.contents);
        }

        self.sources.deinit(self.allocator);
    }
};

test "load a source file" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create the test file.
    try tmp.dir.writeFile(io, .{
        .sub_path = "main.zig",
        .data = "const answer = 42;",
    });

    // Get the absolute path to the temporary directory.
    const root_path = try tmp.parent_dir.realPathFileAlloc(
        io,
        &tmp.sub_path,
        allocator,
    );
    defer allocator.free(root_path);

    var manager = try SourceManager.init(allocator, root_path);
    defer manager.deinit();

    const id = try manager.loadSource(io, "main.zig");

    const source = manager.getSourceFile(id).?;

    try std.testing.expectEqualStrings("main.zig", source.relative_path);
    try std.testing.expectEqualStrings("const answer = 42;", source.contents);
}

test "load multiple source files" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{
        .sub_path = "main.zig",
        .data = "pub fn main() void {}",
    });

    try tmp.dir.writeFile(io, .{
        .sub_path = "parser.zig",
        .data = "pub const Parser = struct {};",
    });

    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    const root_path = try std.fmt.allocPrint(
        allocator,
        "{s}/.zig-cache/tmp/{s}",
        .{ cwd, &tmp.sub_path },
    );
    defer allocator.free(root_path);

    var manager = try SourceManager.init(allocator, root_path);
    defer manager.deinit();

    const main_id = try manager.loadSource(io, "main.zig");
    const parser_id = try manager.loadSource(io, "parser.zig");

    try std.testing.expectEqual(@as(usize, 0), main_id.raw);
    try std.testing.expectEqual(@as(usize, 1), parser_id.raw);

    const main_source = manager.getSourceFile(main_id).?;
    const parser_source = manager.getSourceFile(parser_id).?;

    try std.testing.expectEqualStrings("main.zig", main_source.relative_path);
    try std.testing.expectEqualStrings(
        "pub fn main() void {}",
        main_source.contents,
    );

    try std.testing.expectEqualStrings("parser.zig", parser_source.relative_path);
    try std.testing.expectEqualStrings(
        "pub const Parser = struct {};",
        parser_source.contents,
    );
}

test "getSourceFile returns null for an unknown ID" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    const root_path = try std.fmt.allocPrint(
        allocator,
        "{s}/.zig-cache/tmp/{s}",
        .{ cwd, &tmp.sub_path },
    );
    defer allocator.free(root_path);

    var manager = try SourceManager.init(allocator, root_path);
    defer manager.deinit();

    const result = manager.getSourceFile(SourceId.init(42));

    try std.testing.expect(result == null);
}

test "loadSource returns an error for a nonexistent file" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    const root_path = try std.fmt.allocPrint(
        allocator,
        "{s}/.zig-cache/tmp/{s}",
        .{ cwd, &tmp.sub_path },
    );
    defer allocator.free(root_path);

    var manager = try SourceManager.init(allocator, root_path);
    defer manager.deinit();

    try std.testing.expectError(
        error.FileNotFound,
        manager.loadSource(io, "does-not-exist.zig"),
    );

    try std.testing.expectEqual(@as(usize, 0), manager.sources.items.len);
}

test "sourceProvider returns registered sources" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "src", .default_dir);

    try tmp.dir.writeFile(io, .{
        .sub_path = "src/main.zig",
        .data = "pub fn main() void {}",
    });

    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    const root_path = try allocator.print(
        "{s}/.zig-cache/tmp/{s}",
        .{ cwd, &tmp.sub_path },
    );
    defer allocator.free(root_path);

    var manager = try SourceManager.init(allocator, root_path);
    defer manager.deinit();

    const id = try manager.loadSource(io, "src/main.zig");

    const provider = manager.sourceProvider();

    const source = provider.getSource(id) orelse
        return error.SourceNotFound;

    try std.testing.expectEqualStrings(
        "src/main.zig",
        source.path,
    );

    try std.testing.expectEqualStrings(
        "pub fn main() void {}",
        source.text,
    );
}

test "sourceProvider returns null for an unknown source ID" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    const root_path = try std.fmt.allocPrint(
        allocator,
        "{s}/.zig-cache/tmp/{s}",
        .{ cwd, &tmp.sub_path },
    );
    defer allocator.free(root_path);

    var manager = try SourceManager.init(allocator, root_path);
    defer manager.deinit();

    const provider = manager.sourceProvider();

    const source = provider.getSource(SourceId.init(42));

    try std.testing.expect(source == null);
}

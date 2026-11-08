//! Lex command.
//!
//! Scans a source file and prints its token stream.

const std = @import("std");

const args_module = @import("../cli/args.zig");
const LexArgs = args_module.LexArgs;

const token_module = @import("../lexer/token.zig");
const Token = token_module.Token;
const TokenKind = token_module.TokenKind;

const span_module = @import("../source/span.zig");
const Span = span_module.Span;

const source_module = @import("../source/source.zig");
const SourceId = source_module.SourceId;
const Source = source_module.Source;
const SourceProvider = source_module.SourceProvider;

const diagnostic_module = @import("../diagnostics/diagnostic.zig");
const Diagnostic = diagnostic_module.Diagnostic;
const Severity = diagnostic_module.Severity;

const diagnostic_writer_module = @import("../diagnostics/writer.zig");
const DiagnosticWriter = diagnostic_writer_module.DiagnosticWriter;

const lexer_module = @import("../lexer/lexer.zig");
const Lexer = lexer_module.Lexer;
const TokenResult = lexer_module.TokenResult;

/// The id for the file being lexed.
const SOURCE_ID = 0;

pub fn run(
    args: LexArgs,
    io: std.Io,
    backing_allocator: std.mem.Allocator,
) !void {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const source_text = try std.Io.Dir.cwd().readFileAlloc(
        io,
        args.file,
        allocator,
        .unlimited,
    );

    var tokens = try std.ArrayList(Token).initCapacity(allocator, 0);
    var diagnostics = try std.ArrayList(Diagnostic).initCapacity(allocator, 0);

    var lexer = Lexer.init(.{ .value = SOURCE_ID }, source_text);

    token_loop: while (true) {
        const result = lexer.nextToken();
        switch (result) {
            .token => |tok| {
                const new_token = try tokens.addOne(allocator);
                new_token.* = tok;

                if (tok.kind == TokenKind.eof) {
                    break :token_loop;
                }
            },
            .diagnostic => |diag| {
                const new_diag = try diagnostics.addOne(allocator);
                new_diag.* = diag;
            },
        }
    }

    if (diagnostics.items.len > 0) {
        var provider = LexCommandSourceProvider.init(
            source_text,
            args.file,
        );
        try writeDiagnostics(diagnostics.items, io, provider.provider());
        return error.DiagnosticsEncountered;
    }

    try printTokens(tokens.items, args.file, source_text, io, allocator);
}

fn printTokens(
    tokens: []const Token,
    filename: []const u8,
    source_text: []const u8,
    io: std.Io,
    allocator: std.mem.Allocator,
) !void {
    var location_width = "LOCATION".len;
    var kind_width = "KIND".len;

    for (tokens) |token| {
        const location = try getTokenLocation(
            token.span,
            filename,
            source_text,
            allocator,
        );

        location_width = @max(location_width, location.len);
        kind_width = @max(kind_width, @tagName(token.kind).len);
    }

    const stdout = std.Io.File.stdout();

    try writePadded(stdout, io, "LOCATION", location_width);
    try stdout.writeStreamingAll(io, "  ");
    try writePadded(stdout, io, "KIND", kind_width);
    try stdout.writeStreamingAll(io, "  LEXEME\n");

    try writeRepeated(stdout, io, '-', location_width);
    try stdout.writeStreamingAll(io, "  ");
    try writeRepeated(stdout, io, '-', kind_width);
    try stdout.writeStreamingAll(io, "  ------\n");

    for (tokens) |token| {
        try writeToken(
            token,
            filename,
            source_text,
            io,
            allocator,
            location_width,
            kind_width,
        );
    }
}

fn writeToken(
    token: Token,
    filename: []const u8,
    source_text: []const u8,
    io: std.Io,
    allocator: std.mem.Allocator,
    location_width: usize,
    kind_width: usize,
) !void {
    const stdout = std.Io.File.stdout();

    const location = try getTokenLocation(
        token.span,
        filename,
        source_text,
        allocator,
    );

    try writePadded(stdout, io, location, location_width);
    try stdout.writeStreamingAll(io, "  ");

    try writePadded(
        stdout,
        io,
        @tagName(token.kind),
        kind_width,
    );

    const lexeme = if (token.kind == .eof) "<eof>" else token.lexeme(source_text);

    try stdout.writeStreamingAll(io, "  ");
    try stdout.writeStreamingAll(io, lexeme);
    try stdout.writeStreamingAll(io, "\n");
}

fn writePadded(
    file: std.Io.File,
    io: std.Io,
    text: []const u8,
    width: usize,
) !void {
    try file.writeStreamingAll(io, text);
    try writeRepeated(file, io, ' ', width -| text.len);
}

fn writeRepeated(
    file: std.Io.File,
    io: std.Io,
    character: u8,
    count: usize,
) !void {
    var buffer: [64]u8 = undefined;
    @memset(&buffer, character);

    var remaining = count;

    while (remaining > 0) {
        const length = @min(remaining, buffer.len);
        try file.writeStreamingAll(io, buffer[0..length]);
        remaining -= length;
    }
}

fn getTokenLocation(
    span: Span,
    filename: []const u8,
    source_text: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    var line: usize = 1;
    var column: usize = 1;
    var position: usize = 0;

    while (position < span.start) : (position += 1) {
        if (source_text[position] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }

    return std.fmt.allocPrint(
        allocator,
        "{s}:{d}:{d}",
        .{ filename, line, column },
    );
}

const LexCommandSourceProvider = struct {
    const Self = @This();

    source_text: []const u8,
    path: []const u8,

    pub fn init(source_text: []const u8, path: []const u8) Self {
        return .{
            .source_text = source_text,
            .path = path,
        };
    }

    pub fn getSource(ptr: *const anyopaque, id: SourceId) ?Source {
        const self: *const Self = @ptrCast(@alignCast(ptr));
        if (id.value != SOURCE_ID) {
            return null;
        }

        return .{
            .id = .{ .value = SOURCE_ID },
            .path = self.path,
            .text = self.source_text,
        };
    }

    pub fn provider(self: *const Self) SourceProvider {
        return .{
            .ptr = self,
            .getSourceFn = getSource,
        };
    }
};

fn writeDiagnostics(
    diagnostics: []const Diagnostic,
    io: std.Io,
    provider: SourceProvider,
) !void {
    var diagnostic_writer = DiagnosticWriter.init(provider);
    var stdout_buffer: [1024]u8 = undefined;

    var stderr_writer = std.Io.File.stderr().writerStreaming(
        io,
        &stdout_buffer,
    );
    const writer = &stderr_writer.interface;

    for (diagnostics) |value| {
        try diagnostic_writer.write(writer, value);
    }

    try writer.flush();
}

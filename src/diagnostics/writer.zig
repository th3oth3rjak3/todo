const std = @import("std");

const diagnostic_module = @import("../diagnostics/diagnostic.zig");
const Diagnostic = diagnostic_module.Diagnostic;
const Severity = diagnostic_module.Severity;

const span_module = @import("../source/span.zig");
const Span = span_module.Span;

const source_module = @import("../source/source.zig");
const Source = source_module.Source;
const SourceId = source_module.SourceId;
const SourceProvider = source_module.SourceProvider;

pub const DiagnosticWriter = struct {
    const Self = @This();

    provider: SourceProvider,

    pub fn init(provider: SourceProvider) Self {
        return .{
            .provider = provider,
        };
    }

    pub fn write(
        self: Self,
        output: *std.Io.Writer,
        diagnostic: Diagnostic,
    ) !void {
        const source = self.provider.getSource(diagnostic.span.source) orelse {
            return error.SourceNotFound;
        };

        const start = @min(diagnostic.span.start, diagnostic.span.end);
        const end = @max(diagnostic.span.start, diagnostic.span.end);

        const location = calculateLocation(source.text, start);
        const final_location = calculateLocation(source.text, end);

        const width = gutterWidth(final_location.line);

        try output.print("{s}: {s}\n", .{
            severityName(diagnostic.severity),
            diagnostic.message,
        });

        for (0..width) |_| {
            try output.writeByte(' ');
        }
        try output.print(" --> {s}:{d}:{d}\n", .{
            source.path,
            location.line,
            location.column,
        });

        for (0..width) |_| {
            try output.writeByte(' ');
        }
        try output.writeAll(" |\n");

        try writeSpan(
            output,
            source.text,
            diagnostic.span,
            width,
        );

        try output.writeAll("\n");
    }

    /// Writes a diagnostic header and its source location.
    fn writeHeader(
        output: *std.Io.Writer,
        diagnostic: Diagnostic,
        source: Source,
    ) !void {
        try output.print("{s}: {s}\n", .{
            severityName(diagnostic.severity),
            diagnostic.message,
        });

        const location = calculateLocation(
            source.text,
            diagnostic.span.start,
        );

        try output.print("    --> {s}:{d}:{d}\n", .{
            source.path,
            location.line,
            location.column,
        });
    }

    const Location = struct {
        line: usize,
        column: usize,
    };

    fn calculateLocation(text: []const u8, offset: usize) Location {
        var line: usize = 1;
        var column: usize = 1;

        for (text[0..offset]) |byte| {
            if (byte == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
        }

        return .{
            .line = line,
            .column = column,
        };
    }

    fn severityName(severity: Severity) []const u8 {
        return switch (severity) {
            .err => "Error",
            .warning => "Warning",
            .note => "Note",
        };
    }

    const LineBounds = struct {
        start: usize,
        end: usize,
    };

    fn lineBounds(text: []const u8, offset: usize) LineBounds {
        var start = offset;
        while (start > 0 and text[start - 1] != '\n') {
            start -= 1;
        }

        var end = offset;
        while (end < text.len and text[end] != '\n') {
            end += 1;
        }

        return .{
            .start = start,
            .end = end,
        };
    }

    fn gutterWidth(line_number: usize) usize {
        var width: usize = 1;
        var number = line_number;

        while (number >= 10) {
            number /= 10;
            width += 1;
        }

        return width;
    }

    fn writeSourceLine(
        output: *std.Io.Writer,
        line_number: usize,
        line: []const u8,
        width: usize,
    ) !void {
        const padding = width - gutterWidth(line_number);

        for (0..padding) |_| {
            try output.writeByte(' ');
        }

        try output.print("{d} | {s}\n", .{
            line_number,
            line,
        });
    }

    fn writeSpanLine(
        output: *std.Io.Writer,
        start: usize,
        end: usize,
        width: usize,
    ) !void {
        for (0..width) |_| {
            try output.writeByte(' ');
        }
        try output.writeAll(" | ");

        for (0..start) |_| {
            try output.writeByte(' ');
        }

        const underline_length = @max(end - start, 1);

        for (0..underline_length) |_| {
            try output.writeByte('^');
        }

        try output.writeByte('\n');
    }

    fn writeSpan(
        output: *std.Io.Writer,
        text: []const u8,
        span: Span,
        width: usize,
    ) !void {
        const start = @min(@min(span.start, span.end), text.len);
        const end = @min(@max(span.start, span.end), text.len);

        var current = start;

        while (true) {
            const bounds = lineBounds(text, current);

            const highlight_start = current - bounds.start;
            const highlight_end = @min(end, bounds.end) - bounds.start;

            const line_number = calculateLocation(text, bounds.start).line;

            try writeSourceLine(
                output,
                line_number,
                text[bounds.start..bounds.end],
                width,
            );

            try writeSpanLine(
                output,
                highlight_start,
                highlight_end,
                width,
            );

            if (end <= bounds.end or bounds.end == text.len) break;

            current = bounds.end + 1;
        }
    }
};

test "calculateLocation returns the first line and column" {
    const location = DiagnosticWriter.calculateLocation("hello world", 0);
    try std.testing.expectEqual(1, location.line);
    try std.testing.expectEqual(1, location.column);
}

test "calculateLocation calculates columns correctly" {
    const location = DiagnosticWriter.calculateLocation("hello world", 6);
    try std.testing.expectEqual(1, location.line);
    try std.testing.expectEqual(7, location.column);
}

test "calculateLocation calculates line numbers correctly" {
    const text =
        \\first line
        \\second line
        \\third line
    ;

    const location = DiagnosticWriter.calculateLocation(text, 17);

    try std.testing.expectEqual(2, location.line);
    try std.testing.expectEqual(7, location.column);
}

test "calculateLocation handles multiple lines" {
    const text =
        \\first
        \\second
        \\third
    ;

    const location = DiagnosticWriter.calculateLocation(text, 14);

    try std.testing.expectEqual(3, location.line);
    try std.testing.expectEqual(2, location.column);
}

test "severityName returns the correct names" {
    try std.testing.expectEqualStrings("Error", DiagnosticWriter.severityName(.err));
    try std.testing.expectEqualStrings("Warning", DiagnosticWriter.severityName(.warning));
    try std.testing.expectEqualStrings("Note", DiagnosticWriter.severityName(.note));
}

test "lineBounds finds the boundaries of a line" {
    const text = "first line\nsecond line\nthird line";

    const bounds = DiagnosticWriter.lineBounds(text, 14);

    try std.testing.expectEqual(11, bounds.start);
    try std.testing.expectEqual(22, bounds.end);
}

test "gutterWidth returns the correct width" {
    try std.testing.expectEqual(1, DiagnosticWriter.gutterWidth(1));
    try std.testing.expectEqual(1, DiagnosticWriter.gutterWidth(9));
    try std.testing.expectEqual(2, DiagnosticWriter.gutterWidth(10));
    try std.testing.expectEqual(3, DiagnosticWriter.gutterWidth(100));
    try std.testing.expectEqual(4, DiagnosticWriter.gutterWidth(1000));
}

test "writeSourceLine prints the line number and source text" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSourceLine(
        &output,
        9,
        "const value = 42;",
        2,
    );

    try std.testing.expectEqualStrings(
        " 9 | const value = 42;\n",
        output.buffered(),
    );
}

test "writeSpanLine prints the gutter and underline" {
    const gutter_width = 2;
    const span_start = 5;
    const span_end = 8;

    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpanLine(
        &output,
        span_start,
        span_end,
        gutter_width,
    );

    try std.testing.expectEqualStrings(
        "   |      ^^^\n",
        output.buffered(),
    );
}

test "writeSpan underlines a single-line span" {
    const text = "hello world";
    const span = Span{
        .source = .{ .value = 1 },
        .start = 6,
        .end = 11,
    };

    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, text, span, 1);

    try std.testing.expectEqualStrings(
        "1 | hello world\n" ++
            "  |       ^^^^^\n",
        output.buffered(),
    );
}

test "writeSpan underlines a multi-line span" {
    const text =
        \\first line
        \\second line
        \\third line
    ;

    const span = Span{
        .source = .{ .value = 1 },
        .start = 6,
        .end = 23,
    };

    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, text, span, 1);

    try std.testing.expectEqualStrings(
        "1 | first line\n" ++
            "  |       ^^^^\n" ++
            "2 | second line\n" ++
            "  | ^^^^^^^^^^^\n" ++
            "3 | third line\n" ++
            "  | ^\n",
        output.buffered(),
    );
}

test "writeSpan renders an empty span as one caret" {
    const text = "hello world";
    const span = Span{
        .source = .{ .value = 1 },
        .start = 6,
        .end = 6,
    };

    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, text, span, 1);

    try std.testing.expectEqualStrings(
        "1 | hello world\n" ++
            "  |       ^\n",
        output.buffered(),
    );
}

test "writeSpan normalizes a backwards span" {
    const text = "hello world";
    const span = Span{
        .source = .{ .value = 1 },
        .start = 11,
        .end = 6,
    };

    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, text, span, 1);

    try std.testing.expectEqualStrings(
        "1 | hello world\n" ++
            "  |       ^^^^^\n",
        output.buffered(),
    );
}

test "writeSpan renders a single-line span" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, "hello world", .{
        .source = .{ .value = 1 },
        .start = 6,
        .end = 11,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | hello world\n" ++
            "  |       ^^^^^\n",
        output.buffered(),
    );
}

test "writeSpan renders a multi-line span" {
    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, "first line\nsecond line\nthird line", .{
        .source = .{ .value = 1 },
        .start = 6,
        .end = 23,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | first line\n" ++
            "  |       ^^^^\n" ++
            "2 | second line\n" ++
            "  | ^^^^^^^^^^^\n" ++
            "3 | third line\n" ++
            "  | ^\n",
        output.buffered(),
    );
}

test "writeSpan renders a backwards span" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, "hello world", .{
        .source = .{ .value = 1 },
        .start = 11,
        .end = 6,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | hello world\n" ++
            "  |       ^^^^^\n",
        output.buffered(),
    );
}

test "writeSpan renders an empty span" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, "hello world", .{
        .source = .{ .value = 1 },
        .start = 6,
        .end = 6,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | hello world\n" ++
            "  |       ^\n",
        output.buffered(),
    );
}

test "writeSpan renders a span covering an entire line" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, "hello\nworld", .{
        .source = .{ .value = 1 },
        .start = 0,
        .end = 5,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | hello\n" ++
            "  | ^^^^^\n",
        output.buffered(),
    );
}

test "writeSpan ending at a line boundary does not render the next line" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, "first\nsecond", .{
        .source = .{ .value = 1 },
        .start = 1,
        .end = 5,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | first\n" ++
            "  |  ^^^^\n",
        output.buffered(),
    );
}

test "writeSpan starting at a line boundary renders the correct line" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, "first\nsecond", .{
        .source = .{ .value = 1 },
        .start = 6,
        .end = 9,
    }, 1);

    try std.testing.expectEqualStrings(
        "2 | second\n" ++
            "  | ^^^\n",
        output.buffered(),
    );
}

test "writeSpan aligns multi-digit line numbers" {
    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    const text = "1\n2\n3\n4\n5\n6\n7\n8\n9\nten";

    try DiagnosticWriter.writeSpan(&output, text, .{
        .source = .{ .value = 1 },
        .start = 18,
        .end = 21,
    }, 2);

    try std.testing.expectEqualStrings(
        "10 | ten\n" ++
            "   | ^^^\n",
        output.buffered(),
    );
}

test "writeSpan clamps a span extending beyond source text" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, "hello", .{
        .source = .{ .value = 1 },
        .start = 2,
        .end = 100,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | hello\n" ++
            "  |   ^^^\n",
        output.buffered(),
    );
}

test "writeSpan clamps a span entirely beyond source text" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, "hello", .{
        .source = .{ .value = 1 },
        .start = 100,
        .end = 200,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | hello\n" ++
            "  |      ^\n",
        output.buffered(),
    );
}

test "writeSpan handles an empty source" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try DiagnosticWriter.writeSpan(&output, "", .{
        .source = .{ .value = 1 },
        .start = 0,
        .end = 100,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | \n" ++
            "  | ^\n",
        output.buffered(),
    );
}

const TestSources = struct {
    source: Source,

    fn getSource(
        ptr: *const anyopaque,
        id: SourceId,
    ) ?Source {
        const self: *const TestSources = @ptrCast(@alignCast(ptr));

        if (id.value != 1) return null;
        return self.source;
    }

    fn provider(self: *const TestSources) SourceProvider {
        return .{
            .ptr = @ptrCast(self),
            .getSourceFn = getSource,
        };
    }
};

test "write renders a diagnostic" {
    const test_sources = TestSources{
        .source = .{
            .id = .{ .value = 1 },
            .path = "src/main.zig",
            .text = "hello world",
        },
    };

    var writer = DiagnosticWriter.init(test_sources.provider());

    const diagnostic = Diagnostic.err(
        "Missing semicolon",
        .{
            .source = .{ .value = 1 },
            .start = 6,
            .end = 11,
        },
    );

    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try writer.write(&output, diagnostic);

    try std.testing.expectEqualStrings(
        "Error: Missing semicolon\n" ++
            "  --> src/main.zig:1:7\n" ++
            "  |\n" ++
            "1 | hello world\n" ++
            "  |       ^^^^^\n\n",
        output.buffered(),
    );
}

test "write returns SourceNotFound when the source is unavailable" {
    const test_sources = TestSources{
        .source = .{
            .id = .{ .value = 1 },
            .path = "src/main.zig",
            .text = "hello world",
        },
    };

    var writer = DiagnosticWriter.init(test_sources.provider());

    const diagnostic = Diagnostic.err(
        "Missing semicolon",
        .{
            .source = .{ .value = 2 },
            .start = 6,
            .end = 11,
        },
    );

    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try std.testing.expectError(
        error.SourceNotFound,
        writer.write(&output, diagnostic),
    );
}

test "write renders an error diagnostic" {
    const test_sources = TestSources{
        .source = .{
            .id = .{ .value = 1 },
            .path = "src/main.zig",
            .text = "hello world",
        },
    };

    var writer = DiagnosticWriter.init(test_sources.provider());

    const diagnostic = Diagnostic.err(
        "Missing semicolon",
        .{
            .source = .{ .value = 1 },
            .start = 6,
            .end = 11,
        },
    );

    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try writer.write(&output, diagnostic);

    try std.testing.expectEqualStrings(
        "Error: Missing semicolon\n" ++
            "  --> src/main.zig:1:7\n" ++
            "  |\n" ++
            "1 | hello world\n" ++
            "  |       ^^^^^\n\n",
        output.buffered(),
    );
}

test "write renders a warning diagnostic" {
    const test_sources = TestSources{
        .source = .{
            .id = .{ .value = 1 },
            .path = "src/main.zig",
            .text = "hello world",
        },
    };

    var writer = DiagnosticWriter.init(test_sources.provider());

    const diagnostic = Diagnostic.warn(
        "Unused variable",
        .{
            .source = .{ .value = 1 },
            .start = 6,
            .end = 11,
        },
    );

    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try writer.write(&output, diagnostic);

    try std.testing.expectEqualStrings(
        "Warning: Unused variable\n" ++
            "  --> src/main.zig:1:7\n" ++
            "  |\n" ++
            "1 | hello world\n" ++
            "  |       ^^^^^\n\n",
        output.buffered(),
    );
}

test "write renders an informational diagnostic" {
    const test_sources = TestSources{
        .source = .{
            .id = .{ .value = 1 },
            .path = "src/main.zig",
            .text = "hello world",
        },
    };

    var writer = DiagnosticWriter.init(test_sources.provider());

    const diagnostic = Diagnostic.note(
        "Consider renaming this variable",
        .{
            .source = .{ .value = 1 },
            .start = 6,
            .end = 11,
        },
    );

    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try writer.write(&output, diagnostic);

    try std.testing.expectEqualStrings(
        "Note: Consider renaming this variable\n" ++
            "  --> src/main.zig:1:7\n" ++
            "  |\n" ++
            "1 | hello world\n" ++
            "  |       ^^^^^\n\n",
        output.buffered(),
    );
}

test "write aligns header gutter with multi-digit line numbers" {
    const test_sources = TestSources{
        .source = .{
            .id = .{ .value = 1 },
            .path = "src/main.zig",
            .text = "1\n2\n3\n4\n5\n6\n7\n8\n9\nten",
        },
    };

    var writer = DiagnosticWriter.init(test_sources.provider());

    const diagnostic = Diagnostic.err(
        "Problem on line ten",
        .{
            .source = .{ .value = 1 },
            .start = 18,
            .end = 21,
        },
    );

    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    try writer.write(&output, diagnostic);

    try std.testing.expectEqualStrings(
        "Error: Problem on line ten\n" ++
            "   --> src/main.zig:10:1\n" ++
            "   |\n" ++
            "10 | ten\n" ++
            "   | ^^^\n\n",
        output.buffered(),
    );
}

test "writeSpan renders a span covering the entire source" {
    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    const text = "first\nsecond\nthird";

    try DiagnosticWriter.writeSpan(&output, text, .{
        .source = .{ .value = 1 },
        .start = 0,
        .end = text.len,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | first\n" ++
            "  | ^^^^^\n" ++
            "2 | second\n" ++
            "  | ^^^^^^\n" ++
            "3 | third\n" ++
            "  | ^^^^^\n",
        output.buffered(),
    );
}

test "writeSpan renders an empty span at EOF" {
    var buffer: [128]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    const text = "hello";

    try DiagnosticWriter.writeSpan(&output, text, .{
        .source = .{ .value = 1 },
        .start = text.len,
        .end = text.len,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | hello\n" ++
            "  |      ^\n",
        output.buffered(),
    );
}

test "writeSpan renders a span crossing an empty line" {
    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    const text = "first\n\nthird";

    try DiagnosticWriter.writeSpan(&output, text, .{
        .source = .{ .value = 1 },
        .start = 2,
        .end = text.len,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | first\n" ++
            "  |   ^^^\n" ++
            "2 | \n" ++
            "  | ^\n" ++
            "3 | third\n" ++
            "  | ^^^^^\n",
        output.buffered(),
    );
}

test "writeSpan renders a backwards multi-line span" {
    var buffer: [256]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    const text = "first line\nsecond line\nthird line";

    try DiagnosticWriter.writeSpan(&output, text, .{
        .source = .{ .value = 1 },
        .start = 23,
        .end = 6,
    }, 1);

    try std.testing.expectEqualStrings(
        "1 | first line\n" ++
            "  |       ^^^^\n" ++
            "2 | second line\n" ++
            "  | ^^^^^^^^^^^\n" ++
            "3 | third line\n" ++
            "  | ^\n",
        output.buffered(),
    );
}

test "write can render multiple diagnostics using the same writer" {
    const test_sources = TestSources{
        .source = .{
            .id = .{ .value = 1 },
            .path = "src/main.zig",
            .text = "hello world",
        },
    };

    var writer = DiagnosticWriter.init(test_sources.provider());

    var buffer: [512]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);

    const first = Diagnostic.err(
        "Missing semicolon",
        .{
            .source = .{ .value = 1 },
            .start = 6,
            .end = 11,
        },
    );

    const second = Diagnostic.warn(
        "Unused variable",
        .{
            .source = .{ .value = 1 },
            .start = 0,
            .end = 5,
        },
    );

    try writer.write(&output, first);
    try writer.write(&output, second);

    try std.testing.expectEqualStrings(
        "Error: Missing semicolon\n" ++
            "  --> src/main.zig:1:7\n" ++
            "  |\n" ++
            "1 | hello world\n" ++
            "  |       ^^^^^\n\n" ++
            "Warning: Unused variable\n" ++
            "  --> src/main.zig:1:1\n" ++
            "  |\n" ++
            "1 | hello world\n" ++
            "  | ^^^^^\n\n",
        output.buffered(),
    );
}

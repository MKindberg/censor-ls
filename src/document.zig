const std = @import("std");
const lsp = @import("lsp.zig");

pub const Document = struct {
    allocator: std.mem.Allocator,
    data: []u8,

    pub fn init(allocator: std.mem.Allocator, content: []const u8) !Document {
        const data = try allocator.dupe(u8, content);
        return Document{
            .allocator = allocator,
            .data = data,
        };
    }

    pub fn deinit(self: Document) void {
        self.allocator.free(self.data);
    }

    pub fn update(self: *Document, content: []const u8) !void {
        self.data = try self.allocator.realloc(self.data, content.len);
        std.mem.copyForwards(u8, self.data, content);
    }

    pub fn find(self: Document, pattern: []const u8) !std.ArrayList(lsp.Range) {
        var hits = std.ArrayList(lsp.Range).init(self.allocator);
        errdefer hits.deinit();
        if (pattern.len == 0) {
            return hits;
        }
        var offset: usize = 0;
        while (std.mem.indexOf(u8, self.data[offset..], pattern)) |i| {
            const idx = i + offset;
            const end_idx = idx + pattern.len;
            offset = end_idx;
            const start_line = std.mem.count(u8, self.data[0..idx], "\n");
            const start_col = if (std.mem.lastIndexOf(u8, self.data[0..idx], "\n")) |n| idx - n - 1 else idx;
            const end_line = start_line + std.mem.count(u8, pattern, "\n");
            const end_col = end_idx - (std.mem.lastIndexOf(u8, self.data[0..end_idx], "\n") orelse 0);
            try hits.append(lsp.Range{
                .start = lsp.Position{
                    .line = start_line,
                    .character = start_col,
                },
                .end = lsp.Position{
                    .line = end_line,
                    .character = end_col,
                },
            });
        }
        return hits;
    }
};

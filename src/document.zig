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

    fn idxToPos(self: Document, idx: usize) ?lsp.Position {
        if (idx > self.data.len) {
            return null;
        }
        const line = std.mem.count(u8, self.data[0..idx], "\n");
        if (line == 0) {
            return .{ .line = 0, .character = idx };
        }
        const col = idx - (std.mem.lastIndexOf(u8, self.data[0..idx], "\n") orelse 0) - 1;
        return .{ .line = line, .character = col };
    }

    fn posToIdx(self: Document, pos: lsp.Position) ?usize {
        var offset: usize = 0;
        var i: usize = 0;
        while (i < pos.line) : (i += 1) {
            if (std.mem.indexOf(u8, self.data[offset..], "\n")) |idx| {
                offset += idx + 1;
            } else return null;
        }
        return offset + pos.character;
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
            const start_pos = self.idxToPos(idx).?;
            const end_pos = self.idxToPos(end_idx).?;
            try hits.append(lsp.Range{
                .start = start_pos,
                .end = end_pos,
            });
        }
        return hits;
    }

    pub fn findInRange(self: Document, range: lsp.Range, pattern: []const u8) ?lsp.Range {
        var start_idx = self.posToIdx(range.start).?;
        start_idx -= @min(start_idx, pattern.len);

        var end_idx = self.posToIdx(range.end).?;
        end_idx = @min(self.data.len, end_idx + pattern.len);

        if (std.mem.indexOf(u8, self.data[start_idx..end_idx], pattern)) |i| {
            const idx = i + start_idx;
            const start_pos = self.idxToPos(idx).?;
            const end_pos = self.idxToPos(idx + pattern.len).?;
            return .{
                .start = start_pos,
                .end = end_pos,
            };
        }
        return null;
    }
};

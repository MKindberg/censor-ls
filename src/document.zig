const std = @import("std");

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
};

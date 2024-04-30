const std = @import("std");
const lsp = @import("lsp.zig");
const Document = @import("document.zig").Document;

pub const State = struct {
    allocator: std.mem.Allocator,
    documents: std.StringHashMap(Document),

    pub fn init(allocator: std.mem.Allocator) State {
        return State{
            .allocator = allocator,
            .documents = std.StringHashMap(Document).init(allocator),
        };
    }
    pub fn deinit(self: *State) void {
        var it = self.documents.iterator();
        while (it.next()) |i| {
            self.allocator.free(i.key_ptr.*);
            i.value_ptr.deinit();
        }
        self.documents.deinit();
    }

    pub fn openDocument(self: *State, name: []u8, content: []const u8) !std.ArrayList(lsp.Diagnostic) {
        const key = try self.allocator.alloc(u8, name.len);
        std.mem.copyForwards(u8, key, name);
        const doc = try Document.init(self.allocator, content);
        try self.documents.put(key, doc);

        var diagnostics = std.ArrayList(lsp.Diagnostic).init(self.allocator);
        errdefer diagnostics.deinit();

        const hits = try doc.find("error");
        defer hits.deinit();
        for (hits.items) |range| {
            try diagnostics.append(.{
                .range = range,
                .severity = 1,
                .source = "censor-lsp",
                .message = "Error Found!",
            });
        }
        return diagnostics;
    }

    pub fn updateDocument(self: *State, name: []u8, content: []const u8) !std.ArrayList(lsp.Diagnostic) {
        var doc = self.documents.getPtr(name).?;
        try doc.update(content);

        var diagnostics = std.ArrayList(lsp.Diagnostic).init(self.allocator);
        errdefer diagnostics.deinit();
        const hits = try doc.find("error");
        defer hits.deinit();
        for (hits.items) |range| {
            try diagnostics.append(.{
                .range = range,
                .severity = 1,
                .source = "censor-lsp",
                .message = "Error Found!",
            });
        }
        return diagnostics;
    }

    pub fn hover(self: *State, id: i32, uri: []u8, pos: lsp.Position) !lsp.Response.Hover {
        _ = pos;
        const buf = try std.fmt.allocPrint(self.allocator, "File: {s} Size: {}", .{ uri, self.documents.get(uri).?.data.len });
        return lsp.Response.Hover.init(id, buf);
    }
    pub fn free(self: *State, buf: []const u8) void {
        self.allocator.free(buf);
    }
};

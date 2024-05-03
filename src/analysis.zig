const std = @import("std");
const lsp = @import("lsp.zig");
const Document = @import("document.zig").Document;
const Config = @import("config.zig").Config;

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

    pub fn openDocument(self: *State, name: []u8, content: []const u8) !void {
        const key = try self.allocator.alloc(u8, name.len);
        std.mem.copyForwards(u8, key, name);
        const doc = try Document.init(self.allocator, content);
        try self.documents.put(key, doc);
    }

    pub fn findDiagnostics(self: State, config: Config, uri: []u8) !std.ArrayList(lsp.Diagnostic) {
        const doc = self.documents.get(uri).?;
        var diagnostics = std.ArrayList(lsp.Diagnostic).init(self.allocator);
        errdefer diagnostics.deinit();

        for (config.items) |item| {
            const hits = try doc.find(item.text);
            defer hits.deinit();
            for (hits.items) |range| {
                try diagnostics.append(.{
                    .range = range,
                    .severity = @intFromEnum(item.severity),
                    .source = "censor-ls",
                    .message = item.message,
                });
            }
        }
        return diagnostics;
    }

    pub fn updateDocument(self: *State, name: []u8, content: []const u8) !void {
        var doc = self.documents.getPtr(name).?;
        try doc.update(content);
    }

    pub fn hover(self: *State, config: Config, id: i32, uri: []u8, pos: lsp.Position) ?lsp.Response.Hover {
        const doc = self.documents.get(uri).?;
        for (config.items) |item| {
            if (doc.findInRange(.{ .start = pos, .end = pos }, item.text) != null) {
                return lsp.Response.Hover.init(id, item.message);
            }
        }
        return null;
    }
    pub fn free(self: *State, buf: []const u8) void {
        self.allocator.free(buf);
    }
};

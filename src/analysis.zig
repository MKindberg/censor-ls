const std = @import("std");
const lsp = @import("lsp.zig");
const Document = @import("document.zig").Document;
const Config = @import("config.zig").Config;

pub const State = struct {
    allocator: std.mem.Allocator,
    documents: std.StringHashMap(DocData),

    pub fn init(allocator: std.mem.Allocator) State {
        return State{
            .allocator = allocator,
            .documents = std.StringHashMap(DocData).init(allocator),
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
        const doc = try DocData.init(self.allocator, content, name);
        try self.documents.put(key, doc);
    }

    pub fn findDiagnostics(self: State, uri: []u8) !std.ArrayList(lsp.Diagnostic) {
        const doc = self.documents.get(uri).?;
        var diagnostics = std.ArrayList(lsp.Diagnostic).init(self.allocator);
        errdefer diagnostics.deinit();

        for (doc.config.items) |item| {
            const hits = try doc.doc.find(item.text);
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

    pub fn updateDocument(self: *State, name: []u8, text: []const u8, range: lsp.Range) !void {
        var doc = self.documents.getPtr(name).?;
        try doc.doc.update(text, range);
    }

    pub fn hover(self: *State, id: i32, uri: []u8, pos: lsp.Position) ?lsp.Response.Hover {
        const doc = self.documents.get(uri).?;
        for (doc.config.items) |item| {
            if (doc.doc.findInRange(.{ .start = pos, .end = pos }, item.text) != null) {
                return lsp.Response.Hover.init(id, item.message);
            }
        }
        return null;
    }
    pub fn free(self: *State, buf: []const u8) void {
        self.allocator.free(buf);
    }
};

const DocData = struct {
    doc: Document,
    config: Config,

    fn init(allocator: std.mem.Allocator, content: []const u8, uri: []const u8) !DocData {
        const doc = try Document.init(allocator, content);

        const prefix = "file://";
        const path = if (std.mem.startsWith(u8, uri, prefix)) uri[prefix.len..] else null;
        const config = try Config.init(allocator, path);

        return DocData{ .doc = doc, .config = config };
    }

    fn deinit(self: DocData) void {
        self.doc.deinit();
        self.config.deinit();
    }
};

const std = @import("std");
const lsp = @import("lsp.zig");
const Document = @import("document.zig").Document;
const Config = @import("config.zig").Config;
const Severity = @import("config.zig").Severity;

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

    pub fn closeDocument(self: *State, name: []u8) void {
        const entry = self.documents.getEntry(name);
        self.allocator.free(entry.?.key_ptr.*);
        entry.?.value_ptr.deinit();
        _ = self.documents.remove(name);
    }

    pub fn getDiagnostics(self: State, uri: []u8) []lsp.Diagnostic {
        return self.documents.get(uri).?.diagnostics.items;
    }

    pub fn updateDocument(self: *State, name: []u8, text: []const u8, range: lsp.Range) !void {
        var doc = self.documents.getPtr(name).?;
        try doc.doc.update(text, range);

        try doc.findDiagnostics(name);
    }

    pub fn hover(self: *State, id: i32, uri: []u8, pos: lsp.Position) ?lsp.Response.Hover {
        const doc = self.documents.get(uri).?;
        for (doc.config.items) |item| {
            if (item.file_end != null and !std.mem.endsWith(u8, uri, item.file_end.?)) continue;
            var iter = doc.doc.findInRange(.{ .start = pos, .end = pos }, item.text);
            if (iter.next() != null) {
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
    diagnostics: std.ArrayList(lsp.Diagnostic),

    const Self = @This();
    fn init(allocator: std.mem.Allocator, content: []const u8, uri: []const u8) !Self {
        const doc = try Document.init(allocator, content);

        const prefix = "file://";
        const path = if (std.mem.startsWith(u8, uri, prefix)) uri[prefix.len..] else null;
        const config = try Config.init(allocator, path);

        const diagnostics = std.ArrayList(lsp.Diagnostic).init(allocator);

        var self = Self{ .doc = doc, .config = config, .diagnostics = diagnostics };
        try self.findDiagnostics(uri);

        return self;
    }

    fn findDiagnostics(self: *Self, uri: []const u8) !void {
        self.diagnostics.clearRetainingCapacity();
        for (self.config.items) |item| {
            if (item.file_end != null and !std.mem.endsWith(u8, uri, item.file_end.?)) continue;
            var iter = self.doc.find(item.text);
            while (iter.next()) |range| {
                if (item.severity == Severity.None) continue;
                try self.diagnostics.append(.{
                    .range = range,
                    .severity = @intFromEnum(item.severity),
                    .source = "censor-ls",
                    .message = item.message,
                });
            }
        }
    }

    fn deinit(self: DocData) void {
        self.doc.deinit();
        self.config.deinit();
        self.diagnostics.deinit();
    }
};

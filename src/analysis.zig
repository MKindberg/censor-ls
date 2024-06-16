const std = @import("std");
const lsp_types = @import("lsp").types;
const Document = @import("lsp").Document;
const Config = @import("config.zig").Config;
const Severity = @import("config.zig").Severity;

pub const State = struct {
    allocator: std.mem.Allocator,
    doc_infos: std.StringHashMap(DocInfo),

    pub fn init(allocator: std.mem.Allocator) State {
        return State{
            .allocator = allocator,
            .doc_infos = std.StringHashMap(DocInfo).init(allocator),
        };
    }
    pub fn deinit(self: *State) void {
        var it = self.doc_infos.iterator();
        while (it.next()) |i| {
            self.allocator.free(i.key_ptr.*);
            i.value_ptr.deinit();
        }
        self.doc_infos.deinit();
    }

    pub fn openDocument(self: *State, name: []const u8) !void {
        const key = try self.allocator.alloc(u8, name.len);
        std.mem.copyForwards(u8, key, name);
        const doc = try DocInfo.init(self.allocator, name);

        try self.doc_infos.put(key, doc);
    }

    pub fn closeDocument(self: *State, name: []const u8) void {
        const entry = self.doc_infos.fetchRemove(name);
        self.allocator.free(entry.?.key);
        entry.?.value.deinit();
    }

    pub fn getDiagnostics(self: State, uri: []u8, document: Document) ![]lsp_types.Diagnostic {
        var info = self.doc_infos.getPtr(uri).?;
        try info.findDiagnostics(uri, document);
        return self.doc_infos.get(uri).?.diagnostics.items;
    }

    pub fn hover(self: *State, id: i32, uri: []u8, document: Document, pos: lsp_types.Position) ?lsp_types.Response.Hover {
        const info = self.doc_infos.get(uri).?;
        for (info.config.items) |item| {
            if (item.file_end != null and !std.mem.endsWith(u8, uri, item.file_end.?)) continue;
            var iter = document.findInRange(.{ .start = pos, .end = pos }, item.text);
            if (iter.next() != null) {
                return lsp_types.Response.Hover.init(id, item.message);
            }
        }
        return null;
    }
    pub fn free(self: *State, buf: []const u8) void {
        self.allocator.free(buf);
    }
};

const DocInfo = struct {
    config: Config,
    diagnostics: std.ArrayList(lsp_types.Diagnostic),

    const Self = @This();
    fn init(allocator: std.mem.Allocator, uri: []const u8) !Self {
        const prefix = "file://";
        const path = if (std.mem.startsWith(u8, uri, prefix)) uri[prefix.len..] else null;
        const config = try Config.init(allocator, path);

        const diagnostics = std.ArrayList(lsp_types.Diagnostic).init(allocator);

        return Self{ .config = config, .diagnostics = diagnostics };
    }

    fn findDiagnostics(self: *Self, uri: []const u8, document: Document) !void {
        self.diagnostics.clearRetainingCapacity();
        for (self.config.items) |item| {
            if (item.file_end != null and !std.mem.endsWith(u8, uri, item.file_end.?)) continue;
            var iter = document.find(item.text);
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

    fn deinit(self: DocInfo) void {
        self.config.deinit();
        self.diagnostics.deinit();
    }
};

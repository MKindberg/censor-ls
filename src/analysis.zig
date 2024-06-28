const std = @import("std");
const lsp = @import("lsp");
const Document = @import("lsp").Document;
const Config = @import("config.zig").Config;
const Severity = @import("config.zig").Severity;

pub const State = struct {
    config: Config,
    diagnostics: std.ArrayList(lsp.types.Diagnostic),

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, uri: []const u8) !Self {
        const prefix = "file://";
        const path = if (std.mem.startsWith(u8, uri, prefix)) uri[prefix.len..] else null;
        const config = try Config.init(allocator, path);

        const diagnostics = std.ArrayList(lsp.types.Diagnostic).init(allocator);

        return Self{ .config = config, .diagnostics = diagnostics };
    }
    pub fn deinit(self: *State) void {
        self.config.deinit();
        self.diagnostics.deinit();
    }

    pub fn getDiagnostics(self: *Self, uri: []const u8, document: Document) ![]lsp.types.Diagnostic {
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
        return self.diagnostics.items;
    }

    pub fn hover(self: *State, uri: []const u8, document: Document, pos: lsp.types.Position) ?[]const u8 {
        for (self.config.items) |item| {
            if (item.file_end != null and !std.mem.endsWith(u8, uri, item.file_end.?)) continue;
            var iter = document.findInRange(.{ .start = pos, .end = pos }, item.text);
            if (iter.next() != null) {
                return item.message;
            }
        }
        return null;
    }

    pub fn codeAction(self: *State, arena: std.mem.Allocator, document: Document, range: lsp.types.Range) ?[]const lsp.types.Response.CodeAction.Result {
        const uri = document.uri;

        for (self.config.items) |item| {
            if (item.file_end != null and !std.mem.endsWith(u8, uri, item.file_end.?)) continue;
            if (item.replacement) |replacement| {
                var it = document.findInRange(range, item.text);
                if (it.next()) |r| {
                    const edit: [1]lsp.types.TextEdit = .{.{ .range = r, .newText = replacement }};

                    std.log.info("Censoring {s} {d}-{d} to {d}-{d}", .{ uri, r.start.line, r.start.character, r.end.line, r.end.character });
                    var change = std.json.ArrayHashMap([]const lsp.types.TextEdit){};
                    change.map.put(arena, uri, arena.dupe(lsp.types.TextEdit, &edit) catch unreachable) catch unreachable;

                    const title = std.fmt.allocPrint(arena, "Change '{s}' to '{s}'", .{ item.text, replacement }) catch unreachable;
                    const action: [1]lsp.types.Response.CodeAction.Result = .{.{ .title = title, .edit = .{ .changes = change } }};

                    return arena.dupe(lsp.types.Response.CodeAction.Result, &action) catch unreachable;
                }
            }
        }
        return null;
    }
};

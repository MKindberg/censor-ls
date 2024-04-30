const std = @import("std");
const lsp = @import("lsp.zig");

pub const State = struct {
    allocator: std.mem.Allocator,
    documents: std.StringHashMap([]u8),

    pub fn init(allocator: std.mem.Allocator) State {
        return State{
            .allocator = allocator,
            .documents = std.StringHashMap([]u8).init(allocator),
        };
    }
    pub fn deinit(self: *State) void {
        self.documents.deinit();
    }

    pub fn openDocument(self: *State, name: []u8, content: []const u8) !std.ArrayList(lsp.Diagnostic) {
        const key = try self.allocator.alloc(u8, name.len);
        std.mem.copyForwards(u8, key, name);
        const data = try self.allocator.alloc(u8, content.len);
        std.mem.copyForwards(u8, data, content);
        try self.documents.put(key, data);

        var diagnostics = std.ArrayList(lsp.Diagnostic).init(self.allocator);
        errdefer diagnostics.deinit();

        if (std.mem.indexOf(u8, content, "error") != null) {
            try diagnostics.append(.{
                .range = .{
                    .start = .{
                        .line = 0,
                        .character = 0,
                    },
                    .end = .{
                        .line = 0,
                        .character = 0,
                    },
                },
                .severity = 1,
                .source = "censor-lsp",
                .message = "Error Found!",
            });
        }
        return diagnostics;
    }

    pub fn updateDocument(self: *State, name: []u8, content: []const u8) !std.ArrayList(lsp.Diagnostic) {
        var data = self.documents.get(name).?;
        data = try self.allocator.realloc(data, content.len);
        std.mem.copyForwards(u8, data, content);
        try self.documents.put(name, data);

        var diagnostics = std.ArrayList(lsp.Diagnostic).init(self.allocator);
        errdefer diagnostics.deinit();
        if (std.mem.indexOf(u8, content, "error") != null) {
            try diagnostics.append(.{
                .range = .{
                    .start = .{
                        .line = 0,
                        .character = 0,
                    },
                    .end = .{
                        .line = 0,
                        .character = 0,
                    },
                },
                .severity = 1,
                .source = "censor-lsp",
                .message = "Error Found!",
            });
        }
        return diagnostics;
    }

    pub fn hover(self: *State, id: i32, uri: []u8, pos: lsp.Request.Hover.Params.Position) !lsp.Response.Hover {
        _ = pos;
        const buf = try std.fmt.allocPrint(self.allocator, "File: {s} Size: {}", .{ uri, self.documents.get(uri).?.len });
        return lsp.Response.Hover.init(id, buf);
    }
    pub fn free(self: *State, buf: []const u8) void {
        self.allocator.free(buf);
    }
};

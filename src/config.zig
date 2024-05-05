const std = @import("std");

pub const Config = struct {
    items: []Item,
    inner: std.ArrayList(Item),

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !Self {
        const inner = std.ArrayList(Item).init(allocator);
        var self = Config{ .items = inner.items, .inner = inner };

        var rel_buf: [256]u8 = undefined;
        var buf_alloc = std.heap.FixedBufferAllocator.init(&rel_buf);
        var abs_buf: [std.posix.PATH_MAX]u8 = undefined;
        var file_buf: [std.posix.PATH_MAX]u8 = undefined;

        var rel = std.ArrayList(u8).init(buf_alloc.allocator());
        try rel.appendSlice(".");
        var path = try std.fs.cwd().realpath(rel.items, &abs_buf);

        while (!std.mem.eql(u8, path, "/")) : ({
            try rel.appendSlice("/..");
            path = try std.fs.cwd().realpath(rel.items, &abs_buf);
        }) {
            const file = try std.fmt.bufPrint(&file_buf, "{s}/.censor.json", .{path});
            std.fs.cwd().access(file, .{}) catch continue;
            try self.parseFile(allocator, file);
        }

        const home = std.posix.getenv("HOME").?;
        var buf: [256]u8 = undefined;

        const config_path = try std.fmt.bufPrint(&buf, "{s}/.config/censor-ls/config.json", .{home});
        try self.parseFile(allocator, config_path);

        return self;
    }

    pub fn deinit(self: Self) void {
        for (self.inner.items) |item| {
            item.deinit(self.inner.allocator);
        }
        self.inner.deinit();
    }

    fn parseFile(self: *Self, allocator: std.mem.Allocator, path: []const u8) !void {
        const config_file = try std.fs.cwd().openFile(path, .{});
        defer config_file.close();
        const config_data = try config_file.readToEndAlloc(allocator, 10000);
        defer allocator.free(config_data);
        try self.parse(allocator, config_data);
    }

    fn parse(self: *Self, allocator: std.mem.Allocator, source: []const u8) !void {
        const parsed = try std.json.parseFromSlice(ParseConfig, allocator, source, .{});
        defer parsed.deinit();

        add_loop: for (parsed.value.items) |item| {
            for (self.inner.items) |existing| {
                if (std.mem.eql(u8, existing.text, item.text)) {
                    continue :add_loop;
                }
            }
            try self.inner.append(try item.duplicate(self.inner.allocator));
        }
        // pointer might have been invalidated when appending
        self.items = self.inner.items;
    }
};

pub const ParseConfig = struct {
    items: []Item,
};

const Item = struct {
    text: []const u8,
    replacement: ?[]const u8,
    severity: Severity = .Error,
    message: []const u8 = "Disallowed text found",

    const Self = @This();
    fn duplicate(self: Self, allocator: std.mem.Allocator) !Item {
        const text = try allocator.dupe(u8, self.text);
        const replacement = if (self.replacement) |s| try allocator.dupe(u8, s) else null;
        const message = try allocator.dupe(u8, self.message);
        return Item{
            .text = text,
            .replacement = replacement,
            .severity = self.severity,
            .message = message,
        };
    }
    fn deinit(self: Item, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.replacement) |s| allocator.free(s);
        allocator.free(self.message);
    }
};

const Severity = enum(u8) {
    Error = 1,
    Warning,
    Info,
    Hint,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Severity {
        _ = options;
        switch (try source.nextAlloc(allocator, .alloc_if_needed)) {
            inline .string, .allocated_string => |s| {
                if (std.mem.eql(u8, s, "error") or std.mem.eql(u8, s, "Error")) {
                    return .Error;
                } else if (std.mem.eql(u8, s, "warning") or std.mem.eql(u8, s, "Warning")) {
                    return .Warning;
                } else if (std.mem.eql(u8, s, "info") or std.mem.eql(u8, s, "Info")) {
                    return .Info;
                } else if (std.mem.eql(u8, s, "hint") or std.mem.eql(u8, s, "Hint")) {
                    return .Hint;
                } else {
                    return error.UnexpectedToken;
                }
            },
            inline .number, .allocated_number => |s| return @enumFromInt(try std.fmt.parseInt(u8, s, 10)),
            else => return error.UnexpectedToken,
        }
    }
};

test "config" {
    const str =
        \\{
        \\    "items": [
        \\        {
        \\            "text": "error",
        \\            "replacement": "warning"
        \\        }
        \\    ]
        \\}
    ;

    const inner = std.ArrayList(Item).init(std.testing.allocator);
    var config = Config{ .items = inner.items, .inner = inner };
    defer config.deinit();
    try config.parse(std.testing.allocator, str);
    try std.testing.expectEqual(config.items.len, 1);
}

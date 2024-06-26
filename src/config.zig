const std = @import("std");

pub const Config = struct {
    items: []Item,
    inner: std.ArrayList(Item),

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, file_path: ?[]const u8) !Self {
        const inner = std.ArrayList(Item).init(allocator);
        var self = Config{ .items = inner.items, .inner = inner };

        if (file_path) |fp| {
            var file_buf: [std.posix.PATH_MAX]u8 = undefined;
            var path: []const u8 = std.fs.path.dirname(fp) orelse "";
            var file = try std.fmt.bufPrint(&file_buf, "{s}/.censor.json", .{path});
            try self.parseFile(allocator, file);

            while (std.fs.path.dirname(path)) |p| : (path = p) {
                file = try std.fmt.bufPrint(&file_buf, "{s}/.censor.json", .{path});
                try self.parseFile(allocator, file);
            }
        }
        const home = std.posix.getenv("HOME").?;
        var buf: [256]u8 = undefined;

        const config_path = try std.fmt.bufPrint(&buf, "{s}/.config/censor-ls/config.json", .{home});
        std.fs.makeDirAbsolute(std.fs.path.dirname(config_path).?) catch {};
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
        const config_file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == std.fs.File.OpenError.FileNotFound) {
                return;
            }
            return err;
        };
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
    replacement: ?[]const u8 = null,
    severity: Severity = .Error,
    message: []const u8 = "Disallowed text found",
    file_end: ?[]const u8 = null,

    const Self = @This();
    fn duplicate(self: Self, allocator: std.mem.Allocator) !Item {
        const text = try allocator.dupe(u8, self.text);
        const replacement = if (self.replacement) |s| try allocator.dupe(u8, s) else null;
        const message = try allocator.dupe(u8, self.message);
        const file_end = if (self.file_end) |s| try allocator.dupe(u8, s) else null;
        return Item{
            .text = text,
            .replacement = replacement,
            .severity = self.severity,
            .message = message,
            .file_end = file_end,
        };
    }
    fn deinit(self: Item, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.replacement) |s| allocator.free(s);
        allocator.free(self.message);
        if (self.file_end) |s| allocator.free(s);
    }
};

pub const Severity = enum(u8) {
    None = 0,
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
                } else if (std.mem.eql(u8, s, "none") or std.mem.eql(u8, s, "None")) {
                    return .None;
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

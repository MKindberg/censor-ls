const std = @import("std");
pub const Config = struct {
    items: []Item,
};

const Item = struct {
    text: []const u8,
    replacement: ?[]const u8,
    severity: Severity = .Error,
    message: []const u8 = "Disallowed text found",
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

    const parsed = try std.json.parseFromSlice(Config, std.testing.allocator, str, .{});
    parsed.deinit();
}

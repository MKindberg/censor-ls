const std = @import("std");

pub const Logger = struct {
    var file: ?std.fs.File = null;

    const Self = @This();
    pub fn init(filename: []const u8) !void {
        Self.file = try std.fs.createFileAbsolute(filename, .{
            .read = false,
        });
    }
    pub fn deinit() void {
        if (Self.file) |f| {
            f.close();
        }
        Self.file = null;
    }
    pub fn log(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = scope;

        const prefix = "[" ++ comptime level.asText() ++ "] ";

        const writer = if (Self.file) |f| f.writer() else std.io.getStdOut().writer();
        nosuspend writer.print(prefix ++ format ++ "\n", args) catch return;
    }
};

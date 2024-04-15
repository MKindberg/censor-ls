const std = @import("std");

pub const Logger = struct {
    file: std.fs.File,
    pub fn init(filename: []const u8) !Logger {
        const file = try std.fs.cwd().createFile(filename, .{
            .read = false,
        });
        return Logger{ .file = file };
    }

    pub fn deinit(self: Logger) void {
        _ = self.file.close();
    }
    pub fn log(self: Logger, comptime message: []const u8, args: anytype) void {
        const time = std.time.milliTimestamp();
        self.file.writer().print("{any}: ", .{time}) catch return;
        _ = self.file.write(": ") catch return;
        self.file.writer().print(message, args) catch return;
        _ = self.file.write("\n") catch return;
    }
};

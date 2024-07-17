const std = @import("std");

const Registry = struct {
    name: []const u8 = "censor-ls",
    description: []const u8 = "Help with avoiding certain words",
    homepage: []const u8 = "https://github.com/mkindberg/censor-ls",
    licenses: []const []const u8 = &[_][]const u8{"MIT"},
    languages: []const []const u8 = &[_][]const u8{},
    categories: []const []const u8 = &[_][]const u8{"LSP"},
    source: Source = .{},
    bin: Bin = .{},

    const Source = struct {
        id: []const u8 = "pkg:github/mkindberg/censor-ls@" ++ @embedFile("version"),
        asset: []const Asset = &[_]Asset{Asset{}},
    };
    const Bin = struct {
        @"censor-ls": []const u8 = "{{source.asset.bin}}",
    };
    const Asset = struct {
        target: []const u8 = "linux_x64",
        file: []const u8 = "censor-ls",
        bin: []const u8 = "censor-ls",
    };

    const Self = @This();
    fn init(allocator: std.mem.Allocator, version: []const u8) !Self {
        const id = try std.fmt.allocPrint(allocator, "pkg:github/mkindberg/censor-ls@{s}", .{version});
        return Registry{ .source = .{ .id = id } };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const res = try std.process.Child.run(.{ .allocator = allocator, .argv = &[_][]const u8{ "git", "tag", "-l" } });
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);
    const stdout = std.mem.trim(u8, res.stdout, "\n");
    var it = std.mem.splitBackwardsScalar(u8, stdout, '\n');
    const version = while (it.next()) |tag| {
        if (tag[0] != 'v') continue;
        break tag;
    } else unreachable;

    const registry = try Registry.init(allocator, version);
    defer allocator.free(registry.source.id);

    var registry_file = try std.fs.cwd().createFile("registry.json", .{});
    defer registry_file.close();
    const regs = [_]Registry{registry};
    try std.json.stringify(regs, .{ .whitespace = .indent_2 }, registry_file.writer());
}

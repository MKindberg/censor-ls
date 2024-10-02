const std = @import("std");

const editorgen = @import("lsp_plugins");

pub fn main() !void {
    var info = editorgen.ServerInfo{
        .name = "censor-ls",
        .description = "Help with avoiding certain words",
        .publisher = "mkindberg",
        .languages = &[_][]const u8{"markdown"},
        .repository = "https://github.com/mkindberg/censor-ls",
        .source_id = "pkg:github/mkindberg/censor-ls",
        .license = "MIT",
    };
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    try editorgen.generate(allocator, info);
    info.languages = &[_][]const u8{};
    try editorgen.generateMasonRegistry(allocator, info);
}

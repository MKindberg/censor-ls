const std = @import("std");
const State = @import("analysis.zig").State;
const lsp = @import("lsp");

const Logger = @import("logger.zig").Logger;

const builtin = @import("builtin");

pub const std_options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = Logger.log,
};

const Lsp = lsp.Lsp(State);

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !u8 {
    const home = std.posix.getenv("HOME").?;
    var buf: [256]u8 = undefined;

    const log_path = try std.fmt.bufPrint(&buf, "{s}/.local/share/censor-ls/log.txt", .{home});
    std.fs.makeDirAbsolute(std.fs.path.dirname(log_path).?) catch {};
    try Logger.init(log_path);
    defer Logger.deinit();

    const server_data = lsp.types.ServerData{
        .capabilities = .{
            .hoverProvider = true,
            .codeActionProvider = true,
        },
        .serverInfo = .{
            .name = "censor-ls",
            .version = "0.3.1",
        },
    };
    var server = Lsp.init(allocator, server_data);
    defer server.deinit();

    server.registerDocOpenCallback(handleOpenDoc);
    server.registerDocChangeCallback(handleChangeDoc);
    server.registerHoverCallback(handleHover);
    server.registerCodeActionCallback(handleCodeAction);

    return server.start();
}

fn handleOpenDoc(arena: std.mem.Allocator, context: *Lsp.Context) void {
    const uri = context.document.uri;
    std.log.info("Opened {s}", .{uri});
    context.state = State.init(allocator, uri) catch unreachable;

    const diagnostics = context.state.?.getDiagnostics(uri, context.document) catch unreachable;

    lsp.writeResponse(arena, lsp.types.Notification.PublishDiagnostics{
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = uri,
            .diagnostics = diagnostics,
        },
    }) catch unreachable;
}
fn handleCloseDoc(_: std.mem.Allocator, context: *Lsp.Context) void {
    const uri = context.document.uri;
    std.log.info("Closed {s}", .{uri});
    context.state.?.deinit();
}

fn handleChangeDoc(arena: std.mem.Allocator, context: *Lsp.Context, _: []lsp.types.ChangeEvent) void {
    const diagnostics = context.state.?.getDiagnostics(context.document.uri, context.document) catch unreachable;

    lsp.writeResponse(arena, lsp.types.Notification.PublishDiagnostics{
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = context.document.uri,
            .diagnostics = diagnostics,
        },
    }) catch unreachable;
}

fn handleHover(_: std.mem.Allocator, context: *Lsp.Context, position: lsp.types.Position) ?[]const u8 {
    return context.state.?.hover(context.document.uri, context.document, position);
}

fn handleCodeAction(arena: std.mem.Allocator, context: *Lsp.Context, range: lsp.types.Range) ?[]const lsp.types.Response.CodeAction.Result {
    return context.state.?.codeAction(arena, context.document, range);
}

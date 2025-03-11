const std = @import("std");
const State = @import("analysis.zig").State;
const lsp = @import("lsp");

const builtin = @import("builtin");

comptime {
    const required_zig = "0.14.0";
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse(required_zig) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("At least zig {s} is required", .{min_zig}));
    }
}

pub const std_options = std.Options{ .log_level = if (builtin.mode == .Debug) .debug else .info, .logFn = lsp.log };

const Lsp = lsp.Lsp(State);

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var server: ?Lsp = null;

pub fn main() !u8 {
    const server_data = lsp.types.ServerData{
        .serverInfo = .{
            .name = "censor-ls",
            .version = @embedFile("version"),
        },
    };
    server = Lsp.init(allocator, server_data);
    defer server.?.deinit();

    server.?.registerDocOpenCallback(handleOpenDoc);
    server.?.registerDocChangeCallback(handleChangeDoc);
    server.?.registerHoverCallback(handleHover);
    server.?.registerCodeActionCallback(handleCodeAction);

    return server.?.start();
}

fn handleOpenDoc(p: Lsp.OpenDocumentParameters) void {
    const uri = p.context.document.uri;
    std.log.info("Opened {s}", .{uri});
    p.context.state = State.init(allocator, uri) catch unreachable;

    const diagnostics = p.context.state.?.getDiagnostics(uri, p.context.document) catch unreachable;

    server.?.writeResponse(p.arena, lsp.types.Notification.PublishDiagnostics{
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

fn handleChangeDoc(p: Lsp.ChangeDocumentParameters) void {
    const diagnostics = p.context.state.?.getDiagnostics(p.context.document.uri, p.context.document) catch unreachable;

    server.?.writeResponse(p.arena, lsp.types.Notification.PublishDiagnostics{
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = p.context.document.uri,
            .diagnostics = diagnostics,
        },
    }) catch unreachable;
}

fn handleHover(p: Lsp.HoverParameters) ?[]const u8 {
    return p.context.state.?.hover(p.context.document.uri, p.context.document, p.position);
}

fn handleCodeAction(p: Lsp.CodeActionParameters) ?[]const lsp.types.Response.CodeAction.Result {
    return p.context.state.?.codeAction(p.arena, p.context.document, p.range);
}

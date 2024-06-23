const std = @import("std");
const State = @import("analysis.zig").State;
const lsp = @import("lsp");
const lsp_types = @import("lsp").types;

const Logger = @import("logger.zig").Logger;

const builtin = @import("builtin");

pub const std_options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = Logger.log,
};

const Lsp = lsp.Lsp(State);

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const home = std.posix.getenv("HOME").?;
    var buf: [256]u8 = undefined;

    const log_path = try std.fmt.bufPrint(&buf, "{s}/.local/share/censor-ls/log.txt", .{home});
    std.fs.makeDirAbsolute(std.fs.path.dirname(log_path).?) catch {};
    try Logger.init(log_path);
    defer Logger.deinit();

    const server_data = lsp_types.ServerData{
        .capabilities = .{
            .hoverProvider = true,
            .codeActionProvider = true,
        },
        .serverInfo = .{
            .name = "censor-ls",
            .version = "0.1.0",
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

fn handleOpenDoc(allocator: std.mem.Allocator, context: *Lsp.Context) void {
    const uri = context.document.uri;
    std.log.info("Opened {s}", .{uri});
    context.state = State.init(allocator, uri) catch unreachable;

    const diagnostics = context.state.?.getDiagnostics(uri, context.document) catch unreachable;

    lsp.writeResponse(allocator, lsp_types.Notification.PublishDiagnostics{
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

fn handleChangeDoc(allocator: std.mem.Allocator, context: *Lsp.Context, _: []lsp.types.ChangeEvent) void {
    const diagnostics = context.state.?.getDiagnostics(context.document.uri, context.document) catch unreachable;

    lsp.writeResponse(allocator, lsp_types.Notification.PublishDiagnostics{
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = context.document.uri,
            .diagnostics = diagnostics,
        },
    }) catch unreachable;
}

fn handleHover(allocator: std.mem.Allocator, context: *Lsp.Context, id: i32, position: lsp.types.Position) void {
    if (context.state.?.hover(id, context.document.uri, context.document, position)) |response| {
        lsp.writeResponse(allocator, response) catch unreachable;

        std.log.info("Sent Hover response", .{});
    }
}

fn handleCodeAction(allocator: std.mem.Allocator, context: *Lsp.Context, id: i32, range: lsp.types.Range) void {
    const uri = context.document.uri;

    const info = context.state.?.doc_info;
    for (info.config.items) |item| {
        if (item.file_end != null and !std.mem.endsWith(u8, uri, item.file_end.?)) continue;
        if (item.replacement) |replacement| {
            var it = context.document.findInRange(range, item.text);
            if (it.next()) |r| {
                const edit: [1]lsp_types.TextEdit = .{.{ .range = r, .newText = replacement }};

                std.log.info("Censoring {s} {d}-{d} to {d}-{d}", .{ uri, r.start.line, r.start.character, r.end.line, r.end.character });
                var change = std.json.ArrayHashMap([]const lsp_types.TextEdit){};
                defer change.deinit(allocator);
                change.map.put(allocator, uri, edit[0..]) catch unreachable;

                var buf: [256]u8 = undefined;
                const title = std.fmt.bufPrint(&buf, "Change '{s}' to '{s}'", .{ item.text, replacement }) catch unreachable;
                const action: [1]lsp_types.Response.CodeAction.Result = .{.{ .title = title, .edit = .{ .changes = change } }};

                const response = lsp_types.Response.CodeAction{ .id = id, .result = action[0..] };

                lsp.writeResponse(allocator, response) catch unreachable;
                return;
            }
        }
    }
}

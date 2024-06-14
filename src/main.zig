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

pub const RunState = enum {
    Run,
    ShutdownOk,
    ShutdownErr,
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const home = std.posix.getenv("HOME").?;
    var buf: [256]u8 = undefined;

    const log_path = try std.fmt.bufPrint(&buf, "{s}/.local/share/censor-ls/log.txt", .{home});
    std.fs.makeDirAbsolute(std.fs.path.dirname(log_path).?) catch {};
    try Logger.init(log_path);
    defer Logger.deinit();

    var state = State.init(allocator);
    defer state.deinit();

    var server = lsp.Lsp(State).init(allocator, &state);

    server.registerDocOpenCallback(handleOpenDoc);
    server.registerDocChangeCallback(handleChangeDoc);
    server.registerDocCloseCallback(handleCloseDoc);
    server.registerHoverCallback(handleHover);
    server.registerCodeActionCallback(handleCodeAction);

    return server.start();
}

fn handleOpenDoc(allocator: std.mem.Allocator, state: *State, params: lsp_types.Notification.DidOpenTextDocument.Params) void {
    const doc = params.textDocument;
    std.log.info("Opened {s}", .{doc.uri});
    std.log.debug("{s}", .{doc.text});
    state.openDocument(doc.uri, doc.text) catch unreachable;

    const diagnostics = state.getDiagnostics(doc.uri);

    lsp.writeResponse(allocator, lsp_types.Notification.PublishDiagnostics{
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = doc.uri,
            .diagnostics = diagnostics,
        },
    }) catch unreachable;
}

fn handleChangeDoc(allocator: std.mem.Allocator, state: *State, params: lsp_types.Notification.DidChangeTextDocument.Params) void {
    for (params.contentChanges) |change| {
        state.updateDocument(params.textDocument.uri, change.text, change.range) catch unreachable;
    }

    std.log.debug("Updated document {s}", .{state.documents.get(params.textDocument.uri).?.doc.text});

    const diagnostics = state.getDiagnostics(params.textDocument.uri);

    lsp.writeResponse(allocator, lsp_types.Notification.PublishDiagnostics{
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = params.textDocument.uri,
            .diagnostics = diagnostics,
        },
    }) catch unreachable;
}

fn handleCloseDoc(_: std.mem.Allocator, state: *State, params: lsp_types.Notification.DidCloseTextDocument.Params) void {
    state.closeDocument(params.textDocument.uri);
}

fn handleHover(allocator: std.mem.Allocator, state: *State, request: lsp_types.Request.Hover) void {
    if (state.hover(request.id, request.params.textDocument.uri, request.params.position)) |response| {
        lsp.writeResponse(allocator, response) catch unreachable;

        std.log.info("Sent Hover response", .{});
    }
}

fn handleCodeAction(allocator: std.mem.Allocator, state: *State, request: lsp_types.Request.CodeAction) void {
    const uri = request.params.textDocument.uri;
    const in_range = request.params.range;

    const doc = state.documents.get(uri).?;
    for (doc.config.items) |item| {
        if (item.file_end != null and !std.mem.endsWith(u8, uri, item.file_end.?)) continue;
        if (item.replacement) |replacement| {
            var it = doc.doc.findInRange(in_range, item.text);
            if (it.next()) |range| {
                const edit: [1]lsp_types.TextEdit = .{.{ .range = range, .newText = replacement }};

                std.log.info("Censoring {s} {d}-{d} to {d}-{d}", .{ uri, range.start.line, range.start.character, range.end.line, range.end.character });
                var change = std.json.ArrayHashMap([]const lsp_types.TextEdit){};
                defer change.deinit(allocator);
                change.map.put(allocator, uri, edit[0..]) catch unreachable;

                var buf: [256]u8 = undefined;
                const title = std.fmt.bufPrint(&buf, "Change '{s}' to '{s}'", .{ item.text, replacement }) catch unreachable;
                const action: [1]lsp_types.Response.CodeAction.Result = .{.{ .title = title, .edit = .{ .changes = change } }};

                const response = lsp_types.Response.CodeAction{ .id = request.id, .result = action[0..] };

                lsp.writeResponse(allocator, response) catch unreachable;
                return;
            }
        }
    }
}

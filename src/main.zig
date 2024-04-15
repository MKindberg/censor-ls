const std = @import("std");
const rpc = @import("rpc.zig");
const lsp = @import("lsp.zig");
const Reader = @import("reader.zig").Reader;
const State = @import("analysis.zig").State;

const Logger = @import("logger.zig").Logger;

pub fn main() !void {
    const home = std.posix.getenv("HOME").?;
    var buf: [256]u8 = undefined;
    const log_path = try std.fmt.bufPrint(&buf, "{s}/.local/share/censor-lsp/log.txt", .{home});
    const logger = try Logger.init(log_path);
    defer logger.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn().reader();

    var reader = Reader.init(allocator, stdin);
    defer reader.deinit();

    var state = State.init(allocator);
    defer state.deinit();

    var header = std.ArrayList(u8).init(allocator);
    defer header.deinit();
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    while (true) {
        logger.log("Waiting for header", .{});
        _ = try reader.readUntilDelimiterOrEof(header.writer(), "\r\n\r\n");

        const content_len_str = "Content-Length: ";
        const content_len = if (std.mem.indexOf(u8, header.items, content_len_str)) |idx|
            try std.fmt.parseInt(usize, header.items[idx + content_len_str.len ..], 10)
        else {
            _ = try std.io.getStdErr().write("Content-Length not found in header\n");
            break;
        };
        header.clearRetainingCapacity();

        const bytes_read = try reader.readN(content.writer(), content_len);
        if (bytes_read != content_len) {
            break;
        }
        defer content.clearRetainingCapacity();

        const decoded = rpc.decodeMessage(allocator, logger, content.items) catch |e| {
            logger.log("Failed to decode message: {any}\n", .{e});
            continue;
        };
        try handleMessage(allocator, &state, logger, decoded);
    }
}

fn writeResponse(allocator: std.mem.Allocator, logger: Logger, msg: anytype) !void {
    const response = try rpc.encodeMessage(allocator, msg);
    defer response.deinit();

    const writer = std.io.getStdOut().writer();
    _ = try writer.write(response.items);
    logger.log("Sent response", .{});
}

fn handleMessage(allocator: std.mem.Allocator, state: *State, logger: Logger, msg: rpc.DecodedMessage) !void {
    logger.log("Received request: {s}", .{msg.method.toString()});

    switch (msg.method) {
        rpc.MethodType.Initialize => {
            try handleInitialize(allocator, logger, msg.content);
        },
        rpc.MethodType.Initialized => {},
        rpc.MethodType.TextDocument_DidOpen => {
            try handleOpenDoc(allocator, state, logger, msg.content);
        },
        rpc.MethodType.TextDocument_DidChange => {
            try handleChangeDoc(allocator, state, logger, msg.content);
        },
        rpc.MethodType.TextDocument_Hover => {
            try handleHover(allocator, state, logger, msg.content);
        },
        rpc.MethodType.TextDocument_CodeAction => {
            try handleCodeAction(allocator, state, logger, msg.content);
        },
    }
}

fn handleInitialize(allocator: std.mem.Allocator, logger: Logger, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.InitializeRequest, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const request = parsed.value;

    const client_info = request.params.clientInfo.?;
    logger.log("Connected to {s} {s}", .{ client_info.name, client_info.version });

    const response_msg = lsp.InitializeResponse.init(request.id);

    try writeResponse(allocator, logger, response_msg);
}

fn handleOpenDoc(allocator: std.mem.Allocator, state: *State, logger: Logger, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.DidOpenTextDocumentNotification, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const doc = parsed.value.params.textDocument;
    logger.log("Opened {s}\n{s}", .{ doc.uri, doc.text });
    const diagnostics = try state.openDocument(doc.uri, doc.text);
    defer diagnostics.deinit();

    try writeResponse(allocator, logger, lsp.PublishDiagnosticsNotification{
        .jsonrpc = "2.0",
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = doc.uri,
            .diagnostics = diagnostics.items,
        },
    });
}

fn handleChangeDoc(allocator: std.mem.Allocator, state: *State, logger: Logger, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.DidChangeTextDocumentNotification, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const doc_params = parsed.value.params;
    logger.log("Changed {s}\n{s}", .{ doc_params.textDocument.uri, doc_params.contentChanges[0].text });
    const diagnostics = try state.updateDocument(doc_params.textDocument.uri, doc_params.contentChanges[0].text);
    defer diagnostics.deinit();

    try writeResponse(allocator, logger, lsp.PublishDiagnosticsNotification{
        .jsonrpc = "2.0",
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = doc_params.textDocument.uri,
            .diagnostics = diagnostics.items,
        },
    });
}

fn handleHover(allocator: std.mem.Allocator, state: *State, logger: Logger, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.HoverRequest, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const request = parsed.value;

    const response = try state.hover(request.id, request.params.textDocument.uri, request.params.position);
    defer state.free(response.result.contents);
    try writeResponse(allocator, logger, response);

    logger.log("Sent Hover response", .{});
}

fn handleCodeAction(allocator: std.mem.Allocator, state: *State, logger: Logger, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.CodeActionRequest, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const uri = parsed.value.params.textDocument.uri;
    var range = parsed.value.params.range;
    range.end.character += 2;

    const edit: [1]lsp.CodeActionResponse.CodeAction.TextEdit = .{.{ .range = range, .newText = "<redacted>" }};

    logger.log("Censoring {s} {d}-{d} to {d}-{d}", .{ uri, range.start.line, range.start.character, range.end.line, range.end.character });
    var change = std.json.ArrayHashMap([]const lsp.CodeActionResponse.CodeAction.TextEdit){};
    defer change.deinit(allocator);
    try change.map.put(allocator, uri, edit[0..]);

    const action: [1]lsp.CodeActionResponse.CodeAction = .{.{ .title = "Censor", .edit = .{ .changes = change } }};

    const response = lsp.CodeActionResponse{ .jsonrpc = "2.0", .id = parsed.value.id, .result = action[0..] };

    try writeResponse(allocator, logger, response);
    _ = state;
}

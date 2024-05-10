const std = @import("std");
const rpc = @import("rpc.zig");
const lsp = @import("lsp.zig");
const Reader = @import("reader.zig").Reader;
const State = @import("analysis.zig").State;

const Logger = @import("logger.zig").Logger;

pub const std_options = .{
    .log_level = .info,
    .logFn = Logger.log,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn().reader();

    const home = std.posix.getenv("HOME").?;
    var buf: [256]u8 = undefined;

    const log_path = try std.fmt.bufPrint(&buf, "{s}/.local/share/censor-ls/log.txt", .{home});
    try Logger.init(log_path);
    defer Logger.deinit();

    var reader = Reader.init(allocator, stdin);
    defer reader.deinit();

    var state = State.init(allocator);
    defer state.deinit();

    var header = std.ArrayList(u8).init(allocator);
    defer header.deinit();
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    while (true) {
        std.log.info("Waiting for header", .{});
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

        const decoded = rpc.decodeMessage(allocator, content.items) catch |e| {
            std.log.info("Failed to decode message: {any}\n", .{e});
            continue;
        };
        try handleMessage(allocator, &state, decoded);
    }
}

fn writeResponse(allocator: std.mem.Allocator, msg: anytype) !void {
    const response = try rpc.encodeMessage(allocator, msg);
    defer response.deinit();

    const writer = std.io.getStdOut().writer();
    _ = try writer.write(response.items);
    std.log.info("Sent response", .{});
}

fn handleMessage(allocator: std.mem.Allocator, state: *State, msg: rpc.DecodedMessage) !void {
    std.log.info("Received request: {s}", .{msg.method.toString()});

    switch (msg.method) {
        rpc.MethodType.Initialize => {
            try handleInitialize(allocator, msg.content);
        },
        rpc.MethodType.Initialized => {},
        rpc.MethodType.TextDocument_DidOpen => {
            try handleOpenDoc(allocator, state, msg.content);
        },
        rpc.MethodType.TextDocument_DidChange => {
            try handleChangeDoc(allocator, state, msg.content);
        },
        rpc.MethodType.TextDocument_Hover => {
            try handleHover(allocator, state, msg.content);
        },
        rpc.MethodType.TextDocument_CodeAction => {
            try handleCodeAction(allocator, state, msg.content);
        },
    }
}

fn handleInitialize(allocator: std.mem.Allocator, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Request.Initialize, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const request = parsed.value;

    const client_info = request.params.clientInfo.?;
    std.log.info("Connected to {s} {s}", .{ client_info.name, client_info.version });

    const response_msg = lsp.Response.Initialize.init(request.id);

    try writeResponse(allocator, response_msg);
}

fn handleOpenDoc(allocator: std.mem.Allocator, state: *State, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Notification.DidOpenTextDocument, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const doc = parsed.value.params.textDocument;
    std.log.info("Opened {s}\n{s}", .{ doc.uri, doc.text });
    try state.openDocument(doc.uri, doc.text);

    const diagnostics = try state.findDiagnostics(doc.uri);
    defer diagnostics.deinit();

    try writeResponse(allocator, lsp.Notification.PublishDiagnostics{
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = doc.uri,
            .diagnostics = diagnostics.items,
        },
    });
}

fn handleChangeDoc(allocator: std.mem.Allocator, state: *State, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Notification.DidChangeTextDocument, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const doc_params = parsed.value.params;

    for (doc_params.contentChanges) |change| {
        try state.updateDocument(doc_params.textDocument.uri, change.text, change.range);
    }

    std.log.info("Updated document {s}", .{state.documents.get(doc_params.textDocument.uri).?.doc.data});

    const diagnostics = try state.findDiagnostics(doc_params.textDocument.uri);
    defer diagnostics.deinit();

    try writeResponse(allocator, lsp.Notification.PublishDiagnostics{
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = doc_params.textDocument.uri,
            .diagnostics = diagnostics.items,
        },
    });
}

fn handleHover(allocator: std.mem.Allocator, state: *State, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Request.Hover, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const request = parsed.value;

    if (state.hover(request.id, request.params.textDocument.uri, request.params.position)) |response| {
        try writeResponse(allocator, response);

        std.log.info("Sent Hover response", .{});
    }
}

fn handleCodeAction(allocator: std.mem.Allocator, state: *State, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Request.CodeAction, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const uri = parsed.value.params.textDocument.uri;
    const in_range = parsed.value.params.range;

    const doc = state.documents.get(uri).?;
    for (doc.config.items) |item| {
        if (item.replacement) |replacement| {
            if (doc.doc.findInRange(in_range, item.text)) |range| {
                const edit: [1]lsp.TextEdit = .{.{ .range = range, .newText = replacement }};

                std.log.info("Censoring {s} {d}-{d} to {d}-{d}", .{ uri, range.start.line, range.start.character, range.end.line, range.end.character });
                var change = std.json.ArrayHashMap([]const lsp.TextEdit){};
                defer change.deinit(allocator);
                try change.map.put(allocator, uri, edit[0..]);

                const action: [1]lsp.Response.CodeAction.Result = .{.{ .title = "Censor", .edit = .{ .changes = change } }};

                const response = lsp.Response.CodeAction{ .id = parsed.value.id, .result = action[0..] };

                try writeResponse(allocator, response);
                return;
            }
        }
    }
}

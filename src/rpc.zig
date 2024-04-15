const std = @import("std");
const Logger = @import("logger.zig").Logger;

pub fn encodeMessage(allocator: std.mem.Allocator, msg: anytype) !std.ArrayList(u8) {
    var res = std.ArrayList(u8).init(allocator);
    errdefer res.deinit();
    try std.json.stringify(msg, .{}, res.writer());

    const length = res.items.len;
    var buf: [32]u8 = undefined;
    const content_len = try std.fmt.bufPrint(&buf, "Content-Length: {any}\r\n\r\n", .{length});

    try res.insertSlice(0, content_len);
    return res;
}

const BaseMessage = struct {
    method: []const u8,
};

pub const MethodType = enum {
    Initialize,
    Initialized,
    TextDocument_DidOpen,
    TextDocument_DidChange,
    TextDocument_Hover,
    TextDocument_CodeAction,

    pub fn toString(self: MethodType) []const u8 {
        switch (self) {
            .Initialize => return "initialize",
            .Initialized => return "initialized",
            .TextDocument_DidOpen => return "textDocument/didOpen",
            .TextDocument_DidChange => return "textDocument/didChange",
            .TextDocument_Hover => return "textDocument/hover",
            .TextDocument_CodeAction => return "textDocument/codeAction",
        }
    }
    pub fn fromString(s: []const u8) !MethodType {
        if (std.mem.eql(u8, s, "initialize")) {
            return MethodType.Initialize;
        } else if (std.mem.eql(u8, s, "initialized")) {
            return MethodType.Initialized;
        } else if (std.mem.eql(u8, s, "textDocument/didOpen")) {
            return MethodType.TextDocument_DidOpen;
        } else if (std.mem.eql(u8, s, "textDocument/didChange")) {
            return MethodType.TextDocument_DidChange;
        } else if (std.mem.eql(u8, s, "textDocument/hover")) {
            return MethodType.TextDocument_Hover;
        } else if (std.mem.eql(u8, s, "textDocument/codeAction")) {
            return MethodType.TextDocument_CodeAction;
        }
        return DecodeError.UnknownMethod;
    }
};

const DecodeError = error{
    InvalidMessage,
    UnknownMethod,
};

pub const DecodedMessage = struct {
    method: MethodType,
    content: []const u8,
};

pub fn decodeMessage(allocator: std.mem.Allocator, logger: Logger, msg: []const u8) !DecodedMessage {
    const parsed = try std.json.parseFromSlice(BaseMessage, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    logger.log("{s}", .{parsed.value.method});
    const method_type = try MethodType.fromString(parsed.value.method);
    return .{ .method = method_type, .content = msg };
}

test "encodeMessage" {
    const Foo = struct {
        x: u32,
        y: u32,
    };
    const foo = Foo{ .x = 42, .y = 37 };
    const encoded = try encodeMessage(std.testing.allocator, foo);
    defer encoded.deinit();
    try std.testing.expect(std.mem.eql(u8, "Content-Length: 15\r\n\r\n{\"x\":42,\"y\":37}", encoded.items));
}

test "decodeMessage" {
    const msg = "Content-Length: 20\r\n\r\n{\"method\":\"init\",\"y\":37}";
    const message = try decodeMessage(std.testing.allocator, msg[0..]);
    try std.testing.expectEqual(message.method, MethodType.Initialize);
}

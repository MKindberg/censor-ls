const std = @import("std");
// const Request = struct {
//     jsonrpc: []u8,
//     id: i32,
//     method: []u8,
// };
//
// const Reposonse = struct {
//     jsonrpc: []u8,
//     id: ?i32,
// };
//
// const Notification = struct {
//     jsonrpc: []u8,
//     method: []u8,
// };

pub const InitializeRequest = struct {
    jsonrpc: []const u8,
    id: i32,
    method: []u8,
    params: InitializeRequestParams,

    const InitializeRequestParams = struct {
        clientInfo: ?ClientInfo,

        const ClientInfo = struct {
            name: []u8,
            version: []u8,
        };
    };
};

pub const InitializeResponse = struct {
    jsonrpc: []const u8,
    id: i32,
    result: InitializeResult,

    const InitializeResult = struct {
        capabilities: ServerCapabilities,
        serverInfo: ServerInfo,

        const ServerCapabilities = struct {
            textDocumentSync: i32,
            hoverProvider: bool,
            codeActionProvider: bool,
        };
    };
    const ServerInfo = struct { name: []const u8, version: []const u8 };

    const Self = @This();

    pub fn init(id: i32) Self {
        return Self{
            .jsonrpc = "2.0",
            .id = id,
            .result = .{
                .capabilities = .{
                    .textDocumentSync = 1,
                    .hoverProvider = true,
                    .codeActionProvider = true,
                },
                .serverInfo = .{
                    .name = "censor-lsp",
                    .version = "0.1",
                },
            },
        };
    }
};

const TextDocumentItem = struct {
    uri: []u8,
    languageId: []u8,
    version: i32,
    text: []u8,
};

const TextDocumentIdentifier = struct {
    uri: []u8,
};

pub const DidOpenTextDocumentNotification = struct {
    jsonrpc: []const u8,
    method: []u8,
    params: Params,

    const Params = struct {
        textDocument: TextDocumentItem,
    };
};

pub const DidChangeTextDocumentNotification = struct {
    jsonrpc: []const u8,
    method: []u8,
    params: Params,

    const Params = struct {
        textDocument: VersionedTextDocumentIdentifier,
        contentChanges: []ChangeEvent,

        const VersionedTextDocumentIdentifier = struct {
            uri: []u8,
            version: i32,
        };
    };

    const ChangeEvent = struct {
        // range: Range,
        // rangeLength: ?i32,
        text: []u8,
    };
};

pub const HoverRequest = struct {
    jsonrpc: []const u8,
    id: i32,
    method: []u8,
    params: Params,

    pub const Params = struct {
        textDocument: TextDocumentIdentifier,
        position: Position,

        pub const Position = struct {
            line: i32,
            character: i32,
        };
    };
};

pub const HoverResponse = struct {
    jsonrpc: []const u8,
    id: i32,
    result: HoverResult,

    const HoverResult = struct {
        contents: []const u8,
    };

    const Self = @This();
    pub fn init(id: i32, contents: []const u8) Self {
        return Self{
            .jsonrpc = "2.0",
            .id = id,
            .result = .{
                .contents = contents,
            },
        };
    }
};

const Range = struct {
    start: Position,
    end: Position,
    const Position = struct {
        line: i32,
        character: i32,
    };
};
pub const CodeActionRequest = struct {
    jsonrpc: []const u8,
    id: i32,
    method: []u8,
    params: Params,

    const Params = struct {
        textDocument: TextDocumentIdentifier,
        range: Range,
        context: CodeActionContext,

        const CodeActionContext = struct {};
    };
};

pub const CodeActionResponse = struct {
    jsonrpc: []const u8,
    id: i32,
    result: []const CodeAction,

    pub const CodeAction = struct {
        title: []const u8,
        // command: ?Command,
        edit: ?WorkspaceEdit,
        // const Command = struct {
        //     title: []const u8,
        //     command: []const u8,
        //     arguments: []const u8,
        // };
        const WorkspaceEdit = struct {
            changes: std.json.ArrayHashMap([]const TextEdit),
        };
        pub const TextEdit = struct {
            range: Range,
            newText: []const u8,
        };
    };
};

pub const PublishDiagnosticsNotification = struct {
    jsonrpc: []const u8,
    method: []const u8,
    params: Params,
    const Params = struct {
        uri: []const u8,
        diagnostics: []const Diagnostic,
    };
};
pub const Diagnostic = struct {
    range: Range,
    severity: i32,
    source: ?[]const u8,
    message: []const u8,
};

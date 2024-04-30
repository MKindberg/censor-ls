const std = @import("std");

pub const Request = struct {
    pub const Initialize = struct {
        jsonrpc: []const u8 = "2.0",
        id: i32,
        method: []u8,
        params: Params,

        const Params = struct {
            clientInfo: ?ClientInfo,

            const ClientInfo = struct {
                name: []u8,
                version: []u8,
            };
        };
    };

    pub const Hover = struct {
        jsonrpc: []const u8 = "2.0",
        id: i32,
        method: []u8,
        params: Params,

        pub const Params = struct {
            textDocument: TextDocumentIdentifier,
            position: Position,
        };
    };
    pub const CodeAction = struct {
        jsonrpc: []const u8 = "2.0",
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
};

pub const Response = struct {
    pub const Initialize = struct {
        jsonrpc: []const u8 = "2.0",
        id: i32,
        result: Result,

        const Result = struct {
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

    pub const Hover = struct {
        jsonrpc: []const u8 = "2.0",
        id: i32,
        result: Result,

        const Result = struct {
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
    pub const CodeAction = struct {
        jsonrpc: []const u8 = "2.0",
        id: i32,
        result: []const Result,

        pub const Result = struct {
            title: []const u8,
            edit: ?WorkspaceEdit,
            const WorkspaceEdit = struct {
                changes: std.json.ArrayHashMap([]const TextEdit),
            };
        };
    };
};

pub const Notification = struct {
    pub const DidOpenTextDocument = struct {
        jsonrpc: []const u8 = "2.0",
        method: []u8,
        params: Params,

        const Params = struct {
            textDocument: TextDocumentItem,
        };
    };

    pub const DidChangeTextDocument = struct {
        jsonrpc: []const u8 = "2.0",
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
            text: []u8,
        };
    };
    pub const PublishDiagnostics = struct {
        jsonrpc: []const u8 = "2.0",
        method: []const u8,
        params: Params,
        const Params = struct {
            uri: []const u8,
            diagnostics: []const Diagnostic,
        };
    };
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

pub const Range = struct {
    start: Position,
    end: Position,
};
pub const Position = struct {
    line: usize,
    character: usize,
};

pub const TextEdit = struct {
    range: Range,
    newText: []const u8,
};

pub const Diagnostic = struct {
    range: Range,
    severity: i32,
    source: ?[]const u8,
    message: []const u8,
};

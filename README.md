# Censor-ls

Censor-ls is a language server that will let you mark words with a diagnostic message and suggest a replacement that can be automatically applied with a code action.

## Installation

Use one of the following methods:
* Download the binary from releases into your path (note that checksum isn't related to the binary)
* Download the repo, install zig 0.14 and run `zig build --release=safe --prefix <install_dir>`
* Install with [mason.nvim](https://github.com/williamboman/mason.nvim) by adding `github:mkindberg/censor-ls` as a registry.

## Setup

### Neovim

Add the following to your config.lua:

```lua
local client = vim.lsp.start_client { name = "censor-ls", cmd = { "<path_to_censor-ls>" }, }

if not client then
    vim.notify("Failed to start censor-ls")
else
    vim.api.nvim_create_autocmd("FileType",
        { pattern = {"<filetypes>", "<to>", "<run>", "<on>"}, callback = function() vim.lsp.buf_attach_client(0, client) end }
    )
end
```

## Configuration

censor-ls will look for files names .censor.json in the directory of the file being edited and all parent directories followed by ~/.config/censor-ls/config.json. Items defined closer to the file will take precedence if they are defined in multiple files.

The file should have the following format:
```json
{
    "items": [
        {
            "text": "<The text to look for",
            "replacement": <The text to replace it with on code action (optional)>",
            "severity": "<error|warning|info|hint|nothing (default: error)>",
            "message": "<A message to display (default: Disallowed text found)>",
            "file_end": "file endings to apply this item for"
        }
    ]
}
```

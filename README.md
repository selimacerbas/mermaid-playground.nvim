# mermaid-playground.nvim

Live-preview Mermaid diagrams from your Markdown code blocks in a browser, powered by
[`live-server.nvim`](https://github.com/barrett-ruth/live-server.nvim).  
Works great with Mermaid’s new **architecture** diagrams and icon packs.

https://github.com/selimacerbas/mermaid-playground.nvim

## Features

- Detects the nearest ```mermaid block (by cursor) or the first in the file.
- Writes it to `./.mermaid-playground/diagram.mmd`.
- Serves a rich **viewer** page at `./.mermaid-playground/index.html` (included in this plugin).
- Auto-reloads in the browser via `live-server.nvim`.
- Theme (dark/light) + Zoom + Fit width/height in viewer.
- Icon packs auto-detected (e.g. `logos:*`) and/or set explicitly.
- Configurable **run-priority**:
  - `nvim` – Neovim drives the preview (page is locked; edits in NVim update the preview).
  - `web` – The page’s textarea drives; NVim won’t overwrite.
  - `both` – NVim keeps writing while the page editor is available.

## Requirements

- Neovim 0.8+ (tested newer).
- [barrett-ruth/live-server.nvim](https://github.com/barrett-ruth/live-server.nvim)

## Installation (lazy.nvim)

```lua
-- ~/.config/nvim/lua/plugins/mermaid-playground.lua
return {
  {
    "barrett-ruth/live-server.nvim",
    cmd = { "LiveServerStart", "LiveServerStop" },
    config = function()
      require("live-server").setup({
        port = 5555,  -- default; change if you like
      })
    end,
  },
  {
    "selimacerbas/mermaid-playground.nvim",
    dependencies = { "barrett-ruth/live-server.nvim" },
    ft = { "markdown", "mdx", "mermaid", "mmd" },
    config = function()
      require("mermaid-playground").setup({
        run_priority = "nvim",       -- 'nvim' | 'web' | 'both'
        select_block = "cursor",     -- 'cursor' | 'first'
        autoupdate_events = { "TextChanged", "TextChangedI", "InsertLeave" },
        mermaid = {
          theme = "dark",            -- 'dark' | 'light'
          fit   = "width",           -- 'none' | 'width' | 'height'
          packs = { "logos" },       -- icon packs to preload in viewer
        },
        live_server = { port = 5555 },
        keymaps = {
          toggle = "<leader>mp",     -- start server + open preview
          render = "<leader>mr",     -- force render current block
          open   = "<leader>mo",     -- open preview URL again
        },
      })
    end,
  },
}

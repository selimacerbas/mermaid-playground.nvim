-- plugin/mermaid-playground.lua
if vim.g.loaded_mermaid_playground then
	return
end
vim.g.loaded_mermaid_playground = true

local M = {}

-- Commands
vim.api.nvim_create_user_command("MermaidPreviewOpen", function()
	require("mermaid_playground").open()
end, {})

vim.api.nvim_create_user_command("MermaidPreviewRefresh", function()
	require("mermaid_playground").refresh()
end, {})

vim.api.nvim_create_user_command("MermaidPreviewStop", function()
	require("mermaid_playground").stop()
end, {})

-- Keymaps (leader mp group): mpo/mpr/mps
local map = function(lhs, rhs, desc)
	vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
end

map("<leader>mpo", "<cmd>MermaidPreviewOpen<cr>", "Mermaid: Open preview")
map("<leader>mpr", "<cmd>MermaidPreviewRefresh<cr>", "Mermaid: Refresh preview")
map("<leader>mps", "<cmd>MermaidPreviewStop<cr>", "Mermaid: Stop preview")

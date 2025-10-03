-- plugin/mermaid-playground.lua
if vim.g.loaded_mermaid_playground then
	return
end
vim.g.loaded_mermaid_playground = true

-- User commands
vim.api.nvim_create_user_command("MermaidPreviewStart", function()
	require("mermaid_playground").start()
end, {})

vim.api.nvim_create_user_command("MermaidPreviewRefresh", function()
	require("mermaid_playground").refresh()
end, {})

vim.api.nvim_create_user_command("MermaidPreviewStop", function()
	require("mermaid_playground").stop()
end, {})

-- Keymaps under <leader>mp group:
-- mps = Start, mpS = Stop, mpr = Re-render
local map = function(lhs, rhs, desc)
	vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
end

map("<leader>mps", "<cmd>MermaidPreviewStart<cr>", "Mermaid: Start preview")
map("<leader>mpS", "<cmd>MermaidPreviewStop<cr>", "Mermaid: Stop preview")
map("<leader>mpr", "<cmd>MermaidPreviewRefresh<cr>", "Mermaid: Re-render")

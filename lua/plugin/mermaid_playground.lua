if vim.g.loaded_mermaid_playground then
	return
end
vim.g.loaded_mermaid_playground = true

local M = require("mermaid_playground")

vim.api.nvim_create_user_command("MermaidOpen", function(opts)
	M.open({ priority = "nvim" })
end, {})

vim.api.nvim_create_user_command("MermaidOpenWeb", function(opts)
	M.open({ priority = "web" })
end, {})

vim.api.nvim_create_user_command("MermaidCopyUrl", function()
	M.copy_url()
end, {})

vim.api.nvim_create_user_command("MermaidTogglePriority", function()
	M.toggle_priority()
end, {})

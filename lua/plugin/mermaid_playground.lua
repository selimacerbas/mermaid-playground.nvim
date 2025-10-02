if vim.g.loaded_mermaid_playground then
	return
end
vim.g.loaded_mermaid_playground = true

local M = require("mermaid_playground")

-- Only one command: start the local live preview server and open the page
vim.api.nvim_create_user_command("MermaidOpen", function()
	M.open()
end, {})

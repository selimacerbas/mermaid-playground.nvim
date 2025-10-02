-- user-facing commands
vim.api.nvim_create_user_command("MermaidPlayground", function()
	require("mermaid-playground").open()
end, { desc = "Open Mermaid playground for the fenced block under cursor" })

vim.api.nvim_create_user_command("MermaidPlaygroundStop", function()
	require("mermaid-playground").stop()
end, { desc = "Stop Mermaid playground local server" })

-- plugin/mermaid-playground.lua
local function define_cmd(name, rhs, opts)
	pcall(vim.api.nvim_del_user_command, name) -- avoids clashes with Lazy stubs
	vim.api.nvim_create_user_command(name, rhs, opts or {})
end

define_cmd("MermaidPlayground", function()
	require("mermaid-playground").open()
end, { desc = "Open Mermaid playground for the fenced block under cursor" })

define_cmd("MermaidPlaygroundStop", function()
	require("mermaid-playground").stop()
end, { desc = "Stop Mermaid playground local server" })

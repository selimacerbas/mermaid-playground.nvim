local util = require("mermaid_playground.util")
local ts = require("mermaid_playground.ts")
local server = require("mermaid_playground.server")

local M = {
	cfg = {
		port = 4070,
		follow = false,
		auto_open = true,
		html_source = nil, -- path to YOUR (patched) HTML; if nil, uses repo templates/index.html
		out_dir = nil, -- where the server serves files
	},
	_follow_au = nil,
	_opened_once = false,
}

local function plugin_root()
	-- path to .../mermaid_playground/init.lua
	local here = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(here, ":h:h:h")
end

local function default_paths()
	local out = util.join(vim.fn.stdpath("run"), "mermaid-playground")
	local tpl = util.join(plugin_root(), "templates", "index.html")
	return out, tpl
end

local function seed_html_if_needed()
	local dst = util.join(M.cfg.out_dir, "index.html")
	local src = M.cfg.html_source or select(2, default_paths())
	util.ensure_dir(M.cfg.out_dir)
	local ok, err = util.copy_if_missing(src, dst)
	if not ok then
		vim.notify("mermaid-playground: " .. tostring(err), vim.log.levels.ERROR)
	end
end

local function write_diagram(code)
	util.ensure_dir(M.cfg.out_dir)
	util.write_file(util.join(M.cfg.out_dir, "diagram.mmd"), code)
end

local function ensure_server()
	local ok = server.ensure(M.cfg.out_dir, M.cfg.port)
	if not ok then
		vim.notify("mermaid-playground: failed to start server", vim.log.levels.ERROR)
		return false
	end
	return true
end

local function open_once()
	if M.cfg.auto_open and not M._opened_once then
		util.open_url(("http://localhost:%d/"):format(M.cfg.port)) -- no ?vim=1 needed
		M._opened_once = true
	end
end

local function render_once()
	seed_html_if_needed()
	if not ensure_server() then
		return
	end
	local code, err = ts.code_at_cursor(0)
	if not code then
		vim.notify("mermaid-playground: " .. err, vim.log.levels.WARN)
		return
	end
	write_diagram(code)
	open_once()
	vim.notify("Mermaid preview updated.", vim.log.levels.INFO, { title = "mermaid-playground" })
end

function M.setup(opts)
	M.cfg = vim.tbl_deep_extend("force", M.cfg, opts or {})
	local out, tpl = default_paths()
	M.cfg.out_dir = M.cfg.out_dir or out
	M.cfg.html_source = M.cfg.html_source or tpl

	vim.api.nvim_create_user_command("MermaidPlayground", render_once, { desc = "Preview Mermaid block at cursor" })

	vim.api.nvim_create_user_command("MermaidPlaygroundOpen", function()
		seed_html_if_needed()
		ensure_server()
		util.open_url(("http://localhost:%d/?vim=1"):format(M.cfg.port))
		M._opened_once = true
	end, {})

	vim.api.nvim_create_user_command("MermaidPlaygroundShutdown", function()
		require("mermaid_playground.server").shutdown()
		M._opened_once = false
		vim.notify("mermaid-playground: server stopped.")
	end, {})

	vim.api.nvim_create_user_command("MermaidPlaygroundFollow", function()
		if M._follow_au then
			return
		end
		local grp = vim.api.nvim_create_augroup("MermaidPlaygroundFollow", { clear = true })
		vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI", "TextChanged", "TextChangedI", "BufEnter" }, {
			group = grp,
			pattern = { "*.md", "*.markdown", "*.mdx" },
			callback = function()
				pcall(render_once)
			end,
		})
		M._follow_au = grp
		open_once()
		vim.notify("mermaid-playground: follow mode enabled.")
	end, {})

	vim.api.nvim_create_user_command("MermaidPlaygroundStop", function()
		if M._follow_au then
			pcall(vim.api.nvim_del_augroup_by_id, M._follow_au)
			M._follow_au = nil
			vim.notify("mermaid-playground: follow mode disabled.")
		end
	end, {})
end

return M

local M = {}

local defaults = {
	port = 4070,
	theme = "dark", -- "dark" | "light"
}

M._opts = vim.deepcopy(defaults)

--- Setup user options
---@param opts table|nil
function M.setup(opts)
	M._opts = vim.tbl_deep_extend("force", defaults, opts or {})
end

local function open_url(url)
	-- Prefer nvim 0.10+ API
	if vim.ui and vim.ui.open then
		local ok = pcall(vim.ui.open, url)
		if ok then
			return
		end
	end
	-- Fallback per OS
	local cmd
	if vim.fn.has("mac") == 1 then
		cmd = { "open", url }
	elseif vim.fn.has("win32") == 1 then
		cmd = { "cmd.exe", "/c", "start", url }
	else
		cmd = { "xdg-open", url }
	end
	vim.fn.jobstart(cmd, { detach = true })
end

--- Resolve path to repo root (where this file lives)
local function plugin_root()
	local info = debug.getinfo(1, "S")
	local src = info and info.source or ""
	src = src:gsub("^@", "")
	return vim.fs.dirname(vim.fs.dirname(src)) -- lua/mermaid-playground/.. -> plugin root
end

--- Public: open the playground for the block under cursor
function M.open()
	local extractor = require("mermaid-playground.extractor")
	local ok, code_or_err = extractor.get_mermaid_block_under_cursor(0)
	if not ok then
		vim.notify("mermaid-playground: " .. (code_or_err or "no mermaid block under cursor"), vim.log.levels.WARN)
		return
	end
	local code = code_or_err

	local srv = require("mermaid-playground.server")
	local root = plugin_root()
	local html_path = vim.fs.joinpath(root, "static", "index.html")

	local started, err = srv.start({
		port = M._opts.port,
		html_path = html_path,
		theme = M._opts.theme,
	})
	if not started then
		vim.notify("mermaid-playground: failed to start server: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	srv.set_current_code(code)
	open_url(string.format("http://127.0.0.1:%d/", M._opts.port))
end

--- Public: stop the server
function M.stop()
	local srv = require("mermaid-playground.server")
	srv.stop()
end

return M

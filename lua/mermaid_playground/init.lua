-- lua/mermaid_playground/init.lua
local ts = require("mermaid_playground.ts")
local util = require("mermaid_playground.util")

local M = {}

M.config = {
	workspace_dir = ".mermaid-live", -- created in the project root (cwd)
	index_name = "index.html",
	diagram_name = "diagram.mmd",
	url = "http://localhost:5555/index.html",
	auto_open = true, -- open browser after start
	copy_index_if_missing = true, -- copy assets/index.html if missing
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

local function ensure_workspace()
	local root = vim.loop.cwd()
	local dir = root .. "/" .. M.config.workspace_dir
	util.mkdirp(dir)
	return dir
end

local function write_index_if_needed(dir)
	local dst = dir .. "/" .. M.config.index_name
	if M.config.copy_index_if_missing and not util.file_exists(dst) then
		local src = util.resolve_asset("assets/index.html")
		if not src then
			error("Could not locate assets/index.html in runtimepath. Make sure the plugin ships it.")
		end
		util.copy_file(src, dst)
	end
	return dst
end

local function write_diagram(dir, text)
	local path = dir .. "/" .. M.config.diagram_name
	util.write_text(path, text)
	return path
end

local function extract_mermaid_under_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local ok, text = pcall(ts.extract_under_cursor, bufnr)
	if ok and text and #text > 0 then
		return text
	end
	-- fallback (scan file with regex)
	local fallback = ts.fallback_scan(bufnr)
	if not fallback or #fallback == 0 then
		error("No ```mermaid fenced code block found under (or above) the cursor")
	end
	return fallback
end

local function with_lcd(dir, fn)
	local prev = vim.fn.getcwd()
	vim.cmd("lcd " .. vim.fn.fnameescape(dir))
	local ok, res = pcall(fn)
	vim.cmd("lcd " .. vim.fn.fnameescape(prev))
	if not ok then
		error(res)
	end
	return res
end

function M.open()
	local text = extract_mermaid_under_cursor()
	local dir = ensure_workspace()
	write_index_if_needed(dir)
	write_diagram(dir, text)

	-- start live-server from the workspace dir
	with_lcd(dir, function()
		vim.cmd("LiveServerStart")
	end)

	if M.config.auto_open then
		-- small delay so the server is listening
		vim.defer_fn(function()
			if vim.ui and vim.ui.open then
				pcall(vim.ui.open, M.config.url)
			else
				util.open_in_browser(M.config.url)
			end
		end, 300)
	end
end

function M.refresh()
	local text = extract_mermaid_under_cursor()
	local dir = ensure_workspace()
	write_diagram(dir, text)
	vim.notify("Mermaid: refreshed diagram.mmd", vim.log.levels.INFO)
end

function M.stop()
	pcall(vim.cmd, "LiveServerStop")
end

return M

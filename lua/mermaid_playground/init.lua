-- lua/mermaid_playground/init.lua
local ts = require("mermaid_playground.ts")
local util = require("mermaid_playground.util")

local M = {}

M.config = {
	workspace_dir = ".mermaid-live", -- created in the project root (cwd)
	index_name = "index.html",
	diagram_name = "diagram.mmd",
	url = "http://localhost:5555/index.html", -- (unused now; live-server opens the browser)
	copy_index_if_missing = true, -- copy assets/index.html if missing
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

local function ensure_workspace()
	local root = vim.loop.cwd()
	local dir = vim.fs.joinpath(root, M.config.workspace_dir)
	util.mkdirp(dir)
	return dir
end

local function write_index_if_needed(dir)
	local dst = vim.fs.joinpath(dir, M.config.index_name)
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
	local path = vim.fs.joinpath(dir, M.config.diagram_name)
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

function M.open()
	local text = extract_mermaid_under_cursor()
	local dir = ensure_workspace()
	write_index_if_needed(dir)
	write_diagram(dir, text)

	-- Start live-server explicitly in the WORKSPACE DIR so / serves our index.html.
	-- Also avoid opening a second tab ourselves; live-server will open the browser.
	local arg_dir = vim.fn.fnameescape(dir)
	pcall(vim.cmd, "LiveServerStop " .. arg_dir) -- stop existing server for this dir, if any
	vim.cmd("LiveServerStart " .. arg_dir)
end

function M.refresh()
	local text = extract_mermaid_under_cursor()
	local dir = ensure_workspace()
	write_diagram(dir, text)
	vim.notify("Mermaid: refreshed diagram.mmd", vim.log.levels.INFO)
end

function M.stop()
	local dir = ensure_workspace()
	local arg_dir = vim.fn.fnameescape(dir)
	pcall(vim.cmd, "LiveServerStop " .. arg_dir)
end

return M

-- lua/mermaid_playground/init.lua
local ts = require("mermaid_playground.ts")
local util = require("mermaid_playground.util")

local M = {}

M.config = {
	workspace_dir = ".mermaid-live", -- created in the project cwd
	index_name = "index.html",
	diagram_name = "diagram.mmd",
	copy_index_if_missing = true,

	-- Auto refresh settings
	auto_refresh = true,
	auto_refresh_events = { "InsertLeave", "TextChanged", "TextChangedI" },
	notify_on_refresh = false, -- set true if you want :echo for every write
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Internal state
M._augroup = nil
M._active_bufnr = nil
M._last_text_by_buf = {}

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

local function extract_mermaid_under_cursor(bufnr)
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

local function maybe_refresh_from_cursor(bufnr, silent)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local ok, text = pcall(ts.extract_under_cursor, bufnr)
	if not ok or not text or #text == 0 then
		return false
	end
	if M._last_text_by_buf[bufnr] == text then
		return false
	end
	local dir = ensure_workspace()
	write_diagram(dir, text)
	M._last_text_by_buf[bufnr] = text
	if not silent and M.config.notify_on_refresh then
		vim.notify("Mermaid updated", vim.log.levels.INFO)
	end
	return true
end

local function set_autocmds_for_buffer(bufnr)
	if not M.config.auto_refresh then
		return
	end
	if M._augroup then
		pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
	end
	M._augroup = vim.api.nvim_create_augroup("MermaidPlaygroundAuto", { clear = true })

	for _, ev in ipairs(M.config.auto_refresh_events) do
		vim.api.nvim_create_autocmd(ev, {
			group = M._augroup,
			buffer = bufnr,
			callback = function()
				-- Try to refresh silently; if cursor not in mermaid block, do nothing.
				pcall(maybe_refresh_from_cursor, bufnr, true)
			end,
			desc = "Mermaid Playground auto-refresh",
		})
	end
end

function M.start()
	local bufnr = vim.api.nvim_get_current_buf()
	M._active_bufnr = bufnr

	local text = extract_mermaid_under_cursor(bufnr)
	local dir = ensure_workspace()
	write_index_if_needed(dir)
	write_diagram(dir, text)
	M._last_text_by_buf[bufnr] = text

	-- Set buffer-local autocmds for auto refresh
	set_autocmds_for_buffer(bufnr)

	-- Start live-server for THIS directory; live-server will open the browser once.
	local arg_dir = vim.fn.fnameescape(dir)
	pcall(vim.cmd, "LiveServerStop " .. arg_dir) -- avoid duplicate processes
	vim.cmd("LiveServerStart " .. arg_dir)
end

function M.refresh()
	local bufnr = vim.api.nvim_get_current_buf()
	local changed = maybe_refresh_from_cursor(bufnr, false)
	if not changed and M.config.notify_on_refresh then
		vim.notify("Mermaid: no changes detected", vim.log.levels.INFO)
	end
end

function M.stop()
	if M._augroup then
		pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
		M._augroup = nil
	end
	local dir = ensure_workspace()
	local arg_dir = vim.fn.fnameescape(dir)
	pcall(vim.cmd, "LiveServerStop " .. arg_dir)
end

return M

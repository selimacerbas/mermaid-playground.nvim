-- lua/mermaid_playground/init.lua
local ts = require("mermaid_playground.ts")
local util = require("mermaid_playground.util")

local M = {}

-- Resolve ~/.config (or $XDG_CONFIG_HOME) cross-platform, then append "mermaid-playground"
local function default_workspace_dir()
	local cfg = os.getenv("XDG_CONFIG_HOME")
	if not cfg or #cfg == 0 then
		local home = vim.loop.os_homedir() or vim.fn.expand("~")
		cfg = vim.fs.joinpath(home, ".config")
	end
	return vim.fs.joinpath(cfg, "mermaid-playground")
end

M.config = {
	-- GLOBAL workspace: ~/.config/mermaid-playground
	workspace_dir = default_workspace_dir(),

	index_name = "index.html",
	diagram_name = "diagram.mmd",

	-- Do NOT overwrite a user's global index.html by default
	overwrite_index_on_start = false,

	-- Auto refresh & debounce
	auto_refresh = true,
	auto_refresh_events = { "InsertLeave", "TextChanged", "TextChangedI", "BufWritePost" },
	debounce_ms = 450,
	notify_on_refresh = false,
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Internal state
M._augroup = nil
M._active_bufnr = nil
M._last_text_by_buf = {}
M._server_running = false
M._debounce_seq = 0

local function ensure_workspace()
	local dir = M.config.workspace_dir or default_workspace_dir()
	util.mkdirp(dir)
	return dir
end

local function write_index(dir)
	local dst = vim.fs.joinpath(dir, M.config.index_name)
	local src = util.resolve_asset("assets/index.html")
	if not src then
		error("Could not locate assets/index.html in runtimepath. Make sure the plugin ships it.")
	end
	util.copy_file(src, dst)
	return dst
end

local function write_index_if_needed(dir)
	if M.config.overwrite_index_on_start then
		return write_index(dir)
	end
	local dst = vim.fs.joinpath(dir, M.config.index_name)
	if not util.file_exists(dst) then
		return write_index(dir)
	end
	return dst
end

local function write_diagram(dir, text)
	local path = vim.fs.joinpath(dir, M.config.diagram_name)
	util.write_text(path, text)
	return path
end

local function extract_mermaid_under_cursor_strict(bufnr)
	local ok, text = pcall(ts.extract_under_cursor, bufnr)
	if ok and text and #text > 0 then
		return text
	end
	return nil
end

local function extract_mermaid_from_standalone_file(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")
	if not content or #content == 0 then
		error("Mermaid file appears to be empty")
	end
	return content
end

local function extract_mermaid_under_cursor(bufnr)
	local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

	-- Handle standalone mermaid files (.mmd, .mermaid)
	if filetype == "mermaid" or filetype == "mmd" then
		return extract_mermaid_from_standalone_file(bufnr)
	end

	-- Handle markdown files with Tree-sitter
	local text = extract_mermaid_under_cursor_strict(bufnr)
	if text and #text > 0 then
		return text
	end

	-- Fallback regex scan for markdown files
	local fallback = ts.fallback_scan(bufnr)
	if not fallback or #fallback == 0 then
		error("No ```mermaid fenced code block found under (or above) the cursor")
	end
	return fallback
end

local function maybe_refresh_from_cursor(bufnr, silent)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
	local text

	-- Handle standalone mermaid files (.mmd, .mermaid)
	if filetype == "mermaid" or filetype == "mmd" then
		local ok, result = pcall(extract_mermaid_from_standalone_file, bufnr)
		if not ok or not result or #result == 0 then
			return false
		end
		text = result
	else
		-- Handle markdown files
		text = extract_mermaid_under_cursor_strict(bufnr)
		if (not text) or (#text == 0) then
			local ok_fallback, fb = pcall(ts.fallback_scan, bufnr)
			if not ok_fallback or not fb or #fb == 0 then
				return false
			end
			text = fb
		end
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

local function debounced_refresh(bufnr)
	M._debounce_seq = M._debounce_seq + 1
	local this_call = M._debounce_seq
	vim.defer_fn(function()
		if this_call ~= M._debounce_seq then
			return
		end
		pcall(maybe_refresh_from_cursor, bufnr, true)
	end, M.config.debounce_ms)
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
				debounced_refresh(bufnr)
			end,
			desc = "Mermaid Playground auto-refresh (debounced)",
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

	set_autocmds_for_buffer(bufnr)

	-- Start live-server ONCE, serving the global workspace
	if not M._server_running then
		local arg_dir = vim.fn.fnameescape(dir)
		vim.cmd("LiveServerStart " .. arg_dir)
		M._server_running = true
	end
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
	M._server_running = false
end

return M

-- lua/markdown_preview/init.lua
local ts = require("markdown_preview.ts")
local util = require("markdown_preview.util")
local ls_server = require("live_server.server")

local M = {}

M.config = {
	port = 8421,
	open_browser = true,

	content_name = "content.md",
	index_name = "index.html",

	-- nil = per-buffer workspace (recommended); set a path to override
	workspace_dir = nil,

	overwrite_index_on_start = true,

	auto_refresh = true,
	auto_refresh_events = { "InsertLeave", "TextChanged", "TextChangedI", "BufWritePost" },
	debounce_ms = 300,
	notify_on_refresh = false,
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Internal state
M._augroup = nil
M._active_bufnr = nil
M._last_text_by_buf = {}
M._server_instance = nil
M._debounce_seq = 0
M._workspace_dir = nil

---------------------------------------------------------------------------
-- Workspace
---------------------------------------------------------------------------

local function resolve_workspace(bufnr)
	if M.config.workspace_dir then
		return M.config.workspace_dir
	end
	return util.workspace_for_buffer(bufnr)
end

local function ensure_workspace(bufnr)
	local dir = resolve_workspace(bufnr)
	util.mkdirp(dir)
	return dir
end

---------------------------------------------------------------------------
-- Index HTML
---------------------------------------------------------------------------

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

---------------------------------------------------------------------------
-- Content writing (unified: markdown or mermaid)
---------------------------------------------------------------------------

local function extract_mermaid_under_cursor_strict(bufnr)
	local ok, text = pcall(ts.extract_under_cursor, bufnr)
	if ok and text and #text > 0 then
		return text
	end
	return nil
end

local function extract_mermaid_under_cursor(bufnr)
	local text = extract_mermaid_under_cursor_strict(bufnr)
	if text and #text > 0 then
		return text
	end
	local fallback = ts.fallback_scan(bufnr)
	if not fallback or #fallback == 0 then
		error("No ```mermaid fenced code block found under (or above) the cursor")
	end
	return fallback
end

---Get the content to write based on filetype.
---Markdown buffers: entire buffer.
---Mermaid files (.mmd, .mermaid): entire buffer wrapped in mermaid fence.
---Others: mermaid block under cursor wrapped in fence.
---@param bufnr integer
---@return string
local function get_content(bufnr)
	local ft = vim.bo[bufnr].filetype
	if ft == "markdown" then
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		return table.concat(lines, "\n")
	end
	-- .mmd / .mermaid files: treat entire buffer as mermaid
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if bufname:match("%.mmd$") or bufname:match("%.mermaid$") then
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		return "```mermaid\n" .. table.concat(lines, "\n") .. "\n```\n"
	end
	-- Other filetypes: extract mermaid block under cursor, wrap in code fence
	local mermaid_text = extract_mermaid_under_cursor(bufnr)
	return "```mermaid\n" .. mermaid_text .. "\n```\n"
end

---Same as get_content but never errors (returns nil on failure).
---@param bufnr integer
---@return string|nil
local function get_content_safe(bufnr)
	local ok, text = pcall(get_content, bufnr)
	if ok and text and #text > 0 then
		return text
	end
	return nil
end

local function write_content(dir, text)
	local path = vim.fs.joinpath(dir, M.config.content_name)
	util.write_text(path, text)
	return path
end

---------------------------------------------------------------------------
-- Refresh logic
---------------------------------------------------------------------------

local function maybe_refresh(bufnr, silent)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local text = get_content_safe(bufnr)
	if not text then
		return false
	end

	if M._last_text_by_buf[bufnr] == text then
		return false
	end

	local dir = ensure_workspace(bufnr)
	write_content(dir, text)
	M._last_text_by_buf[bufnr] = text

	-- Notify live-server of the content change for immediate SSE push
	if M._server_instance then
		pcall(ls_server.reload, M._server_instance, M.config.content_name)
	end

	if not silent and M.config.notify_on_refresh then
		vim.notify("Markdown preview updated", vim.log.levels.INFO)
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
		pcall(maybe_refresh, bufnr, true)
	end, M.config.debounce_ms)
end

---------------------------------------------------------------------------
-- Autocmds
---------------------------------------------------------------------------

local function set_autocmds_for_buffer(bufnr)
	if not M.config.auto_refresh then
		return
	end
	if M._augroup then
		pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
	end
	M._augroup = vim.api.nvim_create_augroup("MarkdownPreviewAuto", { clear = true })

	for _, ev in ipairs(M.config.auto_refresh_events) do
		vim.api.nvim_create_autocmd(ev, {
			group = M._augroup,
			buffer = bufnr,
			callback = function()
				debounced_refresh(bufnr)
			end,
			desc = "Markdown Preview auto-refresh (debounced)",
		})
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function M.start()
	local bufnr = vim.api.nvim_get_current_buf()
	M._active_bufnr = bufnr

	local ok_content, text = pcall(get_content, bufnr)
	if not ok_content then
		vim.notify("Markdown Preview: " .. tostring(text), vim.log.levels.ERROR)
		return
	end
	local dir = ensure_workspace(bufnr)
	M._workspace_dir = dir

	write_index_if_needed(dir)
	write_content(dir, text)
	M._last_text_by_buf[bufnr] = text

	set_autocmds_for_buffer(bufnr)

	-- Start live-server if not already running
	if not M._server_instance then
		local index_path = vim.fs.joinpath(dir, M.config.index_name)
		local ok, inst = pcall(ls_server.start, {
			port = M.config.port,
			root = dir,
			default_index = index_path,
			headers = { ["Cache-Control"] = "no-cache" },
			cors = true,
			live = {
				enabled = true,
				inject_script = false,
				debounce = 100,
			},
			features = { dirlist = { enabled = false } },
		})
		if not ok then
			vim.notify(
				("Markdown Preview: failed to start server on port %d — %s"):format(M.config.port, tostring(inst)),
				vim.log.levels.ERROR
			)
			return
		end
		M._server_instance = inst

		if M.config.open_browser then
			vim.defer_fn(function()
				util.open_in_browser(("http://127.0.0.1:%d/"):format(M.config.port))
			end, 200)
		end
	else
		-- Server already running — retarget to this buffer's workspace
		local index_path = vim.fs.joinpath(dir, M.config.index_name)
		pcall(ls_server.update_target, M._server_instance, dir, index_path)
		pcall(ls_server.reload, M._server_instance, M.config.content_name)
	end
end

function M.refresh()
	local bufnr = vim.api.nvim_get_current_buf()
	local changed = maybe_refresh(bufnr, false)
	if not changed and M.config.notify_on_refresh then
		vim.notify("Markdown Preview: no changes detected", vim.log.levels.INFO)
	end
end

function M.stop()
	if M._augroup then
		pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
		M._augroup = nil
	end
	if M._server_instance then
		pcall(ls_server.stop, M._server_instance)
		M._server_instance = nil
	end
	M._workspace_dir = nil
end

return M

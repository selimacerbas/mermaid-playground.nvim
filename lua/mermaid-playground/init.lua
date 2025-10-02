local M = {}

-- Defaults -----------------------------------------------------------
M.config = {
	run_priority = "nvim", -- 'nvim' | 'web' | 'both'
	select_block = "cursor", -- 'cursor' | 'first'
	fallback_to_first = true, -- render first block if cursor detection fails
	autoupdate_events = { "TextChanged", "TextChangedI", "InsertLeave" },
	output = { file = "diagram.mmd", html = "index.html" },
	mermaid = { theme = "dark", fit = "width", packs = { "logos" } },
	live_server = { port = 5555 },
	keymaps = { toggle = nil, render = nil, open = nil },

	-- Workspace (keep repo clean by default)
	workspace_mode = "temp", -- 'temp' | 'project'
	workspace_dir = ".mermaid-playground",

	-- Project root resolution
	root_mode = "auto", -- 'auto' | 'git' | 'file' | 'cwd'
	root_markers = { ".git", "package.json", "pyproject.toml" },
}

-- Utils --------------------------------------------------------------
local function join(...)
	return table.concat({ ... }, "/")
end
local function path_exists(p)
	return vim.loop.fs_stat(p) ~= nil
end
local function ensure_dir(path)
	if vim.fn.isdirectory(path) == 0 then
		vim.fn.mkdir(path, "p")
	end
end

local function buf_dir()
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		return vim.fn.getcwd()
	end
	return vim.fn.fnamemodify(name, ":p:h")
end

local function has_marker(dir, markers)
	for _, m in ipairs(markers or {}) do
		if path_exists(dir .. "/" .. m) then
			return true
		end
	end
	return false
end

local function find_ancestor(start, markers)
	local dir = start
	while dir and dir ~= "/" do
		if has_marker(dir, markers) then
			return dir
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break
		end
		dir = parent
	end
	return nil
end

local function resolve_project_root()
	local mode = M.config.root_mode or "auto"
	if mode == "cwd" then
		return vim.fn.getcwd()
	end
	if mode == "file" then
		return buf_dir()
	end
	if mode == "git" then
		return find_ancestor(buf_dir(), { ".git" }) or vim.fn.getcwd()
	end
	return find_ancestor(buf_dir(), M.config.root_markers) or buf_dir() or vim.fn.getcwd()
end

local function slugify(p)
	local s = (p or ""):gsub("[\\/:]+", "_"):gsub("[^%w_%-]", "_")
	s = s:gsub("__+", "_")
	return s
end

local function workspace_dir()
	if M.config.workspace_mode == "project" then
		return join(resolve_project_root(), M.config.workspace_dir)
	else
		local state = vim.fn.stdpath("state") or vim.fn.stdpath("cache")
		return join(state, "mermaid-playground", slugify(resolve_project_root()))
	end
end

local function output_paths()
	local dir = workspace_dir()
	local file = join(dir, M.config.output.file)
	local html = join(dir, M.config.output.html)
	return dir, file, html
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local data = f:read("*a")
	f:close()
	return data
end

local function write_file(path, text)
	ensure_dir(vim.fn.fnamemodify(path, ":h"))
	local f = assert(io.open(path, "w"))
	f:write(text or "")
	f:close()
end

local function url_encode(s)
	return (s:gsub("([^%w%-%_%.%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function plugin_root()
	local matches = vim.api.nvim_get_runtime_file("lua/mermaid-playground/init.lua", false)
	if matches and matches[1] then
		return matches[1]:gsub("/lua/mermaid%-playground/init%.lua$", "")
	end
	return nil
end

local function ensure_viewer()
	local asset_root = plugin_root()
	local asset = asset_root and (asset_root .. "/assets/index.html") or nil
	local dir, _, html = output_paths()
	ensure_dir(dir)
	if vim.fn.filereadable(html) == 0 then
		if asset and vim.fn.filereadable(asset) == 1 then
			write_file(html, assert(read_file(asset)))
		else
			write_file(html, "<!doctype html><title>Mermaid viewer missing</title>")
		end
	end
end

local function open_url(url)
	local sys = vim.loop.os_uname().sysname
	if sys == "Darwin" then
		vim.fn.jobstart({ "open", url }, { detach = true })
	elseif sys:match("Windows") then
		vim.fn.jobstart({ "cmd", "/c", "start", "", url }, { detach = true })
	else
		vim.fn.jobstart({ "xdg-open", url }, { detach = true })
	end
end

-- Fence scanning ------------------------------------------------------
local function fence_open(line)
	-- Matches: ```mermaid, ``` mermaid, ```mermaid {init:...}, ~~~ mermaid, etc.
	local fence, trailing = line:match("^%s*([`~]{3,})%s*(.-)%s*$")
	if not fence then
		return nil
	end
	local char = fence:sub(1, 1)
	local len = #fence
	local lang = nil
	if trailing and #trailing > 0 then
		lang = trailing:match("^([%w_%-%.]+)")
		if lang then
			lang = lang:lower()
		end
	end
	return { char = char, len = len, lang = lang, raw = trailing or "" }
end

local function fence_close(line, char, len)
	local fence = line:match("^%s*([`~]{3,})%s*$")
	if not fence then
		return false
	end
	if fence:sub(1, 1) ~= char then
		return false
	end
	return #fence >= len -- closing can be >= opening length
end

local function find_all_mermaid_blocks(lines)
	local blocks, i = {}, 1
	while i <= #lines do
		local fo = fence_open(lines[i] or "")
		local is_mermaid = false
		if fo then
			if fo.lang == "mermaid" then
				is_mermaid = true
			elseif fo.raw and fo.raw:lower():match("^%s*mermaid[%s{]") then
				is_mermaid = true
			end
		end
		if fo and is_mermaid then
			local start_i = i
			i = i + 1
			while i <= #lines and not fence_close(lines[i] or "", fo.char, fo.len) do
				i = i + 1
			end
			local stop_i = math.min(i, #lines) -- inclusive
			-- body is between fences; allow empty body (we still treat as a block)
			local body = table.concat(vim.list_slice(lines, start_i + 1, stop_i - 1), "\n")
			blocks[#blocks + 1] = { start = start_i, stop = stop_i, body = body }
		else
			i = i + 1
		end
	end
	return blocks
end

local function block_at_cursor(blocks, cursor_lnum)
	-- Inclusive: cursor on opening or closing fence counts as inside
	for _, b in ipairs(blocks) do
		if cursor_lnum >= b.start and cursor_lnum <= b.stop then
			return b
		end
	end
	return nil
end

-- Core ---------------------------------------------------------------
function M.render_current_block()
	-- Read buffer unconditionally (no filetype gate)
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local cur = vim.api.nvim_win_get_cursor(0)[1] -- 1-based line
	local blocks = find_all_mermaid_blocks(lines)

	local chosen
	if M.config.select_block == "cursor" then
		chosen = block_at_cursor(blocks, cur)
		if not chosen and M.config.fallback_to_first then
			chosen = blocks[1]
		end
	else
		chosen = blocks[1]
	end

	if not chosen then
		vim.notify("[mermaid-playground] No mermaid fenced block found (cursor or first).", vim.log.levels.INFO)
		return
	end

	local dir, file = output_paths()
	write_file(file, chosen.body or "")
	vim.notify("[mermaid-playground] wrote " .. file, vim.log.levels.DEBUG)
end

local function ensure_server_started_with_root(root)
	-- Force serving the workspace as root (stop any previous, chdir, start)
	if vim.fn.exists(":LiveServerStop") == 2 then
		vim.cmd("silent! LiveServerStop")
	end
	vim.cmd(("silent! execute 'cd %s'"):format(vim.fn.fnameescape(root)))
	if vim.fn.exists(":LiveServerStart") == 2 then
		vim.cmd(("silent! LiveServerStart %s"):format(vim.fn.fnameescape(root)))
	else
		vim.notify("[mermaid-playground] live-server.nvim not found. Please install it.", vim.log.levels.ERROR)
	end
end

function M.preview_url()
	local packs = table.concat(M.config.mermaid.packs or {}, ",")
	local base = ("http://localhost:%d/%s"):format(M.config.live_server.port, M.config.output.html)
	if M.config.run_priority == "web" then
		return ("%s?theme=%s&fit=%s&packs=%s"):format(base, M.config.mermaid.theme, M.config.mermaid.fit, packs)
	else
		local lock = (M.config.run_priority == "nvim") and "1" or "0"
		return ("%s?src=%s&theme=%s&fit=%s&packs=%s&lock=%s"):format(
			base,
			url_encode(M.config.output.file),
			M.config.mermaid.theme,
			M.config.mermaid.fit,
			packs,
			lock
		)
	end
end

function M.start()
	local dir = workspace_dir()
	ensure_viewer()
	if M.config.run_priority ~= "web" then
		M.render_current_block()
	end
	ensure_server_started_with_root(dir)
	open_url(M.preview_url())
end

function M.stop()
	if vim.fn.exists(":LiveServerStop") == 2 then
		vim.cmd("LiveServerStop")
	end
end

-- Optional helpers for keymaps ---------------------------------------
M._running = false
function M.toggle()
	M._running = not M._running
	if M._running then
		M.start()
	else
		M.stop()
	end
end

function M.open()
	open_url(M.preview_url())
end

-- Setup / keymaps / autocommands ------------------------------------
function M.setup(user)
	M.config = vim.tbl_deep_extend("force", M.config, user or {})

	-- User commands
	vim.api.nvim_create_user_command("MermaidPlaygroundStart", function()
		M.start()
	end, {})
	vim.api.nvim_create_user_command("MermaidPlaygroundStop", function()
		M.stop()
	end, {})
	vim.api.nvim_create_user_command("MermaidPlaygroundRender", function()
		M.render_current_block()
	end, {})
	vim.api.nvim_create_user_command("MermaidPlaygroundOpen", function()
		M.open()
	end, {})

	-- Optional plugin-provided maps (off by default)
	local km = M.config.keymaps or {}
	if km.toggle then
		vim.keymap.set("n", km.toggle, M.toggle, { desc = "Mermaid: toggle preview" })
	end
	if km.render then
		vim.keymap.set("n", km.render, M.render_current_block, { desc = "Mermaid: render current block" })
	end
	if km.open then
		vim.keymap.set("n", km.open, M.open, { desc = "Mermaid: open preview URL" })
	end

	-- Auto-render only when NVim drives
	if M.config.run_priority ~= "web" then
		local grp = vim.api.nvim_create_augroup("MermaidPlaygroundAuto", { clear = true })
		for _, ev in ipairs(M.config.autoupdate_events or {}) do
			vim.api.nvim_create_autocmd(ev, {
				group = grp,
				pattern = { "*.md", "*.markdown", "*.mdx", "*.mmd", "*.mermaid" },
				callback = function()
					M.render_current_block()
				end,
				desc = "Mermaid Playground: render current diagram",
			})
		end
	end
end

return M

local M = {}

-- =========================
-- Config (with safe defaults)
-- =========================
M.config = {
	run_priority = "nvim", -- 'nvim' | 'web' | 'both'
	select_block = "cursor", -- 'cursor' | 'first'
	fallback_to_first = true, -- if cursor match fails, use first mermaid block
	autoupdate_events = { "TextChanged", "TextChangedI", "InsertLeave" },

	mermaid = {
		theme = "dark", -- 'dark' | 'light'
		fit = "width", -- 'none' | 'width' | 'height'
		packs = { "logos" }, -- Iconify packs to preload (e.g. 'logos', 'simple-icons')
	},

	live_server = { port = 5555 },

	-- Workspace: keep your repo clean by default
	workspace_mode = "temp", -- 'temp' | 'project'
	workspace_dir = ".mermaid-playground", -- used only if workspace_mode='project'

	-- Root detection (used to compute per-project temp folder)
	root_mode = "auto", -- 'auto' | 'git' | 'file' | 'cwd'
	root_markers = { ".git", "package.json", "pyproject.toml" },

	-- Optional plugin-provided keymaps (left nil; use your lazy keys)
	keymaps = { toggle = nil, render = nil, open = nil },

	-- Output filenames inside the workspace
	output = {
		file = "diagram.mmd",
		html = "index.html",
	},
}

-- =========================
-- Utils
-- =========================
local function join(...)
	return table.concat({ ... }, "/")
end
local function ensure_dir(path)
	if vim.fn.isdirectory(path) == 0 then
		vim.fn.mkdir(path, "p")
	end
end

local function path_exists(p)
	return vim.loop.fs_stat(p) ~= nil
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

local function system_open(url)
	local sys = vim.loop.os_uname().sysname
	if sys == "Darwin" then
		vim.fn.jobstart({ "open", url }, { detach = true })
	elseif sys:match("Windows") then
		vim.fn.jobstart({ "cmd", "/c", "start", "", url }, { detach = true })
	else
		vim.fn.jobstart({ "xdg-open", url }, { detach = true })
	end
end

-- =========================
-- Fence detection (robust, no TS needed)
-- =========================
local function open_fence(line)
	-- Accepts: ```mermaid, ``` mermaid, ```mermaid {init:...}, ~~~ mermaid, etc.
	local fence, rest = line:match("^%s*([`~]{3,})%s*(.-)%s*$")
	if not fence then
		return nil
	end
	local rest_l = (rest or ""):lower()
	local is_mermaid = rest_l == "mermaid" or rest_l:match("^mermaid%s") or rest_l:match("^mermaid{")
	if not is_mermaid then
		return nil
	end
	return { char = fence:sub(1, 1), len = #fence }
end

local function is_close_fence(line, char, len)
	local f = line:match("^%s*([`~]{3,})%s*$")
	if not f then
		return false
	end
	if f:sub(1, 1) ~= char then
		return false
	end
	return #f >= len -- close can be >= open length
end

local function find_blocks(lines)
	local blocks, i = {}, 1
	while i <= #lines do
		local fo = open_fence(lines[i] or "")
		if fo then
			local start_i = i
			i = i + 1
			while i <= #lines and not is_close_fence(lines[i] or "", fo.char, fo.len) do
				i = i + 1
			end
			local stop_i = math.min(i, #lines)
			local body = table.concat(vim.list_slice(lines, start_i + 1, stop_i - 1), "\n")
			blocks[#blocks + 1] = { start = start_i, stop = stop_i, body = body }
		else
			i = i + 1
		end
	end
	return blocks
end

local function block_under_cursor(blocks, lnum)
	-- inclusive: fences count as inside
	for _, b in ipairs(blocks) do
		if lnum >= b.start and lnum <= b.stop then
			return b
		end
	end
	return nil
end

-- =========================
-- Core: render under cursor
-- =========================
function M.render_current_block()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if #lines == 0 then
		vim.notify("[mermaid-playground] Empty buffer", vim.log.levels.WARN)
		return
	end
	local cur = vim.api.nvim_win_get_cursor(0)[1] -- 1-based
	local blocks = find_blocks(lines)

	local chosen
	if M.config.select_block == "cursor" then
		chosen = block_under_cursor(blocks, cur)
		if not chosen and M.config.fallback_to_first then
			chosen = blocks[1]
		end
	else
		chosen = blocks[1]
	end

	if not chosen then
		vim.notify("[mermaid-playground] No ```mermaid fenced block found (cursor/first).", vim.log.levels.WARN)
		return
	end

	-- normalize indentation (helpful for indented MD)
	local body_lines = {}
	for s in (chosen.body or ""):gmatch("([^\n]*)\n?") do
		table.insert(body_lines, s)
	end
	local min_indent
	for _, l in ipairs(body_lines) do
		local sp = l:match("^(%s*)")
		if sp ~= nil then
			min_indent = min_indent and math.min(min_indent, #sp) or #sp
		end
	end
	if min_indent and min_indent > 0 then
		for i, l in ipairs(body_lines) do
			body_lines[i] = l:sub(min_indent + 1)
		end
	end
	local final = table.concat(body_lines, "\n")

	local dir, file = output_paths()
	write_file(file, final)
	vim.notify("[mermaid-playground] wrote " .. file, vim.log.levels.DEBUG)
end

-- =========================
-- Live-server (serve workspace dir, then restore CWD)
-- =========================
local function ensure_server_in(dir)
	local old = vim.fn.getcwd()
	if vim.fn.exists(":LiveServerStop") == 2 then
		vim.cmd("silent! LiveServerStop")
	end
	vim.cmd(("silent! execute 'cd %s'"):format(vim.fn.fnameescape(dir)))
	if vim.fn.exists(":LiveServerStart") == 2 then
		vim.cmd("silent! LiveServerStart")
	else
		vim.notify("[mermaid-playground] live-server.nvim not found", vim.log.levels.ERROR)
	end
	vim.cmd(("silent! execute 'cd %s'"):format(vim.fn.fnameescape(old)))
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
	ensure_server_in(dir)
	system_open(M.preview_url())
end

function M.stop()
	if vim.fn.exists(":LiveServerStop") == 2 then
		vim.cmd("silent! LiveServerStop")
	end
end

-- Helpers for keymaps
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
	system_open(M.preview_url())
end

function M.render()
	M.render_current_block()
end

-- =========================
-- Setup / commands / autos
-- =========================
function M.setup(user)
	M.config = vim.tbl_deep_extend("force", M.config, user or {})

	vim.api.nvim_create_user_command("MermaidPlaygroundStart", function()
		M.start()
	end, {})
	vim.api.nvim_create_user_command("MermaidPlaygroundStop", function()
		M.stop()
	end, {})
	vim.api.nvim_create_user_command("MermaidPlaygroundOpen", function()
		M.open()
	end, {})
	vim.api.nvim_create_user_command("MermaidPlaygroundRender", function()
		M.render()
	end, {})

	local km = M.config.keymaps or {}
	if km.toggle then
		vim.keymap.set("n", km.toggle, M.toggle, { desc = "Mermaid: toggle preview" })
	end
	if km.render then
		vim.keymap.set("n", km.render, M.render, { desc = "Mermaid: render current block" })
	end
	if km.open then
		vim.keymap.set("n", km.open, M.open, { desc = "Mermaid: open preview URL" })
	end

	if M.config.run_priority ~= "web" then
		local grp = vim.api.nvim_create_augroup("MermaidPlaygroundAuto", { clear = true })
		for _, ev in ipairs(M.config.autoupdate_events or {}) do
			vim.api.nvim_create_autocmd(ev, {
				group = grp,
				pattern = { "*.md", "*.markdown", "*.mdx", "*.mmd", "*.mermaid" },
				callback = function()
					M.render()
				end,
				desc = "Mermaid Playground: render current diagram",
			})
		end
	end
end

return M

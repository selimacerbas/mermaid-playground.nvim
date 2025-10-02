local M = {}

-- Defaults -----------------------------------------------------------
M.config = {
	run_priority = "nvim", -- 'nvim' | 'web' | 'both'
	select_block = "cursor", -- 'cursor' | 'first'
	autoupdate_events = { "TextChanged", "TextChangedI", "InsertLeave" },
	output = {
		dir = ".mermaid-playground",
		file = "diagram.mmd",
		html = "index.html",
	},
	mermaid = {
		theme = "dark", -- 'dark' | 'light'
		fit = "width", -- 'none' | 'width' | 'height'
		packs = { "logos" }, -- pre-load packs in viewer
	},
	live_server = {
		port = 5555,
	},
	keymaps = { -- plugin-defined maps (you can disable and map in lazy `keys`)
		toggle = nil, -- e.g. "<leader>mpp" to enable here
		render = nil, -- e.g. "<leader>mpr"
		open = nil, -- e.g. "<leader>mpo"
	},
	-- NEW: project root resolution (so live-server serves the right folder)
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

local function resolve_root()
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
	-- auto
	return find_ancestor(buf_dir(), M.config.root_markers) or buf_dir() or vim.fn.getcwd()
end

local function read_buf_lines(bufnr)
	bufnr = bufnr or 0
	return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function find_mermaid_block(lines, mode, cursor_lnum)
	local start_i, stop_i
	if mode == "cursor" and cursor_lnum then
		for i = cursor_lnum, 1, -1 do
			if lines[i] and lines[i]:match("^```%s*mermaid") then
				start_i = i
				break
			end
		end
		if start_i then
			for i = start_i + 1, #lines do
				if lines[i]:match("^```%s*$") then
					stop_i = i
					break
				end
			end
		end
	end
	if not start_i then
		for i = 1, #lines do
			if lines[i]:match("^```%s*mermaid") then
				start_i = i
				for j = i + 1, #lines do
					if lines[j]:match("^```%s*$") then
						stop_i = j
						break
					end
				end
				break
			end
		end
	end

	if start_i and stop_i and stop_i > start_i + 1 then
		local body = table.concat(vim.list_slice(lines, start_i + 1, stop_i - 1), "\n")
		return body
	end
	return nil
end

local function write_file(path, text)
	local f = assert(io.open(path, "w"))
	f:write(text or "")
	f:close()
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

local function url_encode(s)
	return (s:gsub("([^%w%-%_%.%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- Locate plugin root to copy viewer asset ----------------------------
local function plugin_root()
	local matches = vim.api.nvim_get_runtime_file("lua/mermaid-playground/init.lua", false)
	if matches and matches[1] then
		return matches[1]:gsub("/lua/mermaid%-playground/init%.lua$", "")
	end
	return nil
end

local function output_paths()
	local root = resolve_root()
	local dir = join(root, M.config.output.dir)
	local file = join(dir, M.config.output.file)
	local html = join(dir, M.config.output.html)
	return dir, file, html, root
end

local function ensure_viewer()
	local root_dir = plugin_root()
	local asset = root_dir and (root_dir .. "/assets/index.html") or nil
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

-- Core ---------------------------------------------------------------
function M.render_current_block()
	local buf = vim.api.nvim_get_current_buf()
	local ft = vim.bo[buf].filetype
	if ft ~= "markdown" and ft ~= "md" and ft ~= "mermaid" and ft ~= "mdx" and ft ~= "mmd" then
		vim.notify("[mermaid-playground] Not a Markdown/Mermaid buffer", vim.log.levels.WARN)
		return
	end
	local lines = read_buf_lines(buf)
	local cur = vim.api.nvim_win_get_cursor(0)[1]
	local body = find_mermaid_block(lines, M.config.select_block, cur)
	if not body or trim(body) == "" then
		vim.notify("[mermaid-playground] No ```mermaid block found", vim.log.levels.WARN)
		return
	end
	local dir, file = output_paths()
	ensure_dir(dir)
	write_file(file, body)
	vim.notify("[mermaid-playground] wrote " .. file, vim.log.levels.DEBUG)
end

local function ensure_server_started()
	if vim.fn.exists(":LiveServerStart") == 2 then
		vim.cmd("LiveServerStart")
	else
		vim.notify("[mermaid-playground] live-server.nvim not found. Please install it.", vim.log.levels.ERROR)
	end
end

function M.preview_url()
	local dir, file, html = output_paths()
	local packs = table.concat(M.config.mermaid.packs or {}, ",")
	local base = ("http://localhost:%d/%s/%s"):format(
		M.config.live_server.port,
		M.config.output.dir,
		M.config.output.html
	)

	if M.config.run_priority == "web" then
		-- Page drives; no src= (textarea mode).
		return ("%s?theme=%s&fit=%s&packs=%s"):format(base, M.config.mermaid.theme, M.config.mermaid.fit, packs)
	else
		-- NVim (or both) drives using external file source.
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
	local _, _, _, root = output_paths()
	-- ensure live-server serves the correct directory
	vim.fn.chdir(root)
	ensure_viewer()
	if M.config.run_priority ~= "web" then
		M.render_current_block()
	end
	ensure_server_started()
	open_url(M.preview_url())
end

function M.stop()
	if vim.fn.exists(":LiveServerStop") == 2 then
		vim.cmd("LiveServerStop")
	end
end

-- Optional helpers (so you can map without user commands) -----------
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

	-- Optional plugin-provided keymaps (disabled by default)
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

	-- Autoupdate only when NVim writes the source file
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

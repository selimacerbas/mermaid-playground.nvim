local M = {}

local utils = require("mermaid_playground.utils")
local server = require("mermaid_playground.server")
local html = require("mermaid_playground.html")

local default_cfg = {
	port = 4070,
	browser = nil, -- nil = auto-detect ("open"/"xdg-open"/etc.)
	detect_packs = true, -- auto-detect Iconify packs in the source
	force_regen_html = false, -- rewrite bundled HTML on setup
	html_filename = "index.html", -- served file name
	poll_interval_ms = 1000, -- client polling interval (in HTML)
}

M._cfg = vim.deepcopy(default_cfg)

local function data_dir()
	local dir = vim.fs.joinpath(vim.fn.stdpath("data"), "mermaid-playground", "server")
	vim.fn.mkdir(dir, "p")
	return dir
end

local function html_path()
	return vim.fs.joinpath(data_dir(), M._cfg.html_filename)
end

local function mmd_path()
	return vim.fs.joinpath(data_dir(), "current.mmd")
end

local function ensure_assets()
	-- write index.html (with polling enabled)
	local path = html_path()
	if M._cfg.force_regen_html or (vim.fn.filereadable(path) == 0) then
		local content = html.index_html({ poll_ms = M._cfg.poll_interval_ms })
		local fd = assert(io.open(path, "w"))
		fd:write(content)
		fd:close()
	end
	-- ensure current.mmd exists
	if vim.fn.filereadable(mmd_path()) == 0 then
		local fd = assert(io.open(mmd_path(), "w"))
		fd:write("graph TD\n  A --> B\n")
		fd:close()
	end
end

local function write_current_src(src)
	local fd, err = io.open(mmd_path(), "w")
	if not fd then
		vim.notify("mermaid-playground: cannot write current.mmd: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	fd:write(src or "")
	fd:close()
	return true
end

local function extract_under_cursor()
	local ok, txt = utils.treesitter_mermaid_under_cursor()
	if ok and txt and #txt > 0 then
		return txt
	end
	local ok2, txt2 = utils.regex_mermaid_under_cursor()
	if ok2 and txt2 and #txt2 > 0 then
		return txt2
	end
	return nil
end

local function update_from_cursor()
	local src = extract_under_cursor()
	if not src then
		return false
	end
	if M._cfg.detect_packs then
		-- (optional) nothing extra required; HTML auto-detects packs itself
	end
	return write_current_src(src)
end

local function open_browser_once()
	local url = ("http://127.0.0.1:%d/"):format(M._cfg.port)
	utils.open_in_browser(url, M._cfg.browser)
	vim.notify("Mermaid live preview at " .. url, vim.log.levels.INFO, { title = "mermaid" })
end

-- Public: Start server, write the current block, open browser
function M.open()
	ensure_assets()
	local ok, err = server.ensure_started(M._cfg.port, data_dir())
	if not ok then
		vim.notify("mermaid-playground: " .. tostring(err), vim.log.levels.ERROR)
		return
	end
	-- write an initial snapshot (if any)
	update_from_cursor()
	open_browser_once()
end

function M.setup(opts)
	M._cfg = vim.tbl_deep_extend("force", vim.deepcopy(default_cfg), opts or {})
	ensure_assets()
	-- autocmds: update the preview on InsertLeave and BufWritePost for md/mdx
	local grp = vim.api.nvim_create_augroup("MermaidPlayground", { clear = true })
	vim.api.nvim_create_autocmd({ "InsertLeave" }, {
		group = grp,
		pattern = { "*.md", "*.mdx", "*.markdown" },
		callback = function()
			update_from_cursor()
		end,
		desc = "Update mermaid live preview on InsertLeave",
	})
	vim.api.nvim_create_autocmd({ "BufWritePost" }, {
		group = grp,
		pattern = { "*.md", "*.mdx", "*.markdown" },
		callback = function()
			update_from_cursor()
		end,
		desc = "Update mermaid live preview on save",
	})
end

return M

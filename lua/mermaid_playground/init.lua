local M = {}

local utils = require("mermaid_playground.utils")
local html = require("mermaid_playground.html")

local default_cfg = {
	run_priority = "nvim",
	browser = nil,
	detect_packs = true,
	force_regen_html = false,
	html_filename = "mermaid-playground.html",
}

M._cfg = vim.deepcopy(default_cfg)

local function data_html_path()
	local dir = vim.fs.joinpath(vim.fn.stdpath("data"), "mermaid-playground")
	vim.fn.mkdir(dir, "p")
	return vim.fs.joinpath(dir, M._cfg.html_filename)
end

local function ensure_html()
	local path = data_html_path()
	if M._cfg.force_regen_html or (vim.fn.filereadable(path) == 0) then
		local content = html.index_html()
		local fd = assert(io.open(path, "w"))
		fd:write(content)
		fd:close()
	end
	return path
end

local function build_local_url(src, packs)
	local b64 = utils.base64_urlencode(src) -- URL-safe base64 (no padding)
	local hash = {
		"src=" .. b64,
		"b64=1",
	}
	if packs and #packs > 0 then
		table.insert(hash, "packs=" .. utils.urlencode(table.concat(packs, ",")))
	end
	table.insert(hash, "autorender=1")
	-- theme is remembered inside the page; you can append `theme=dark|light` if you want
	local hash_qs = table.concat(hash, "&")
	local path = ensure_html()
	return "file://" .. path .. "#" .. hash_qs
end

local function build_web_url(src)
	-- Best-effort: Mermaid Live supports `#base64:` in addition to `#pako:`
	-- We use base64 (URL-safe) so we don't ship a deflate dependency.
	local b64 = utils.base64_urlencode(src)
	return "https://mermaid.live/edit#base64:" .. b64
end

local function open_url(url)
	utils.open_in_browser(url, M._cfg.browser)
	vim.notify("Opened Mermaid playground", vim.log.levels.INFO, { title = "mermaid" })
end

local function get_src_under_cursor()
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

function M.open(opts)
	opts = opts or {}
	local src = get_src_under_cursor()
	if not src then
		vim.notify("No mermaid fenced code block under cursor", vim.log.levels.WARN, { title = "mermaid" })
		return
	end
	local packs = {}
	if M._cfg.detect_packs then
		packs = utils.detect_icon_packs(src)
	end

	local priority = (opts.priority or M._cfg.run_priority):lower()
	local url = priority == "web" and build_web_url(src) or build_local_url(src, packs)

	open_url(url)
	M._last_url = url
end

function M.copy_url(opts)
	opts = opts or {}
	local src = get_src_under_cursor()
	if not src then
		vim.notify("No mermaid fenced code block under cursor", vim.log.levels.WARN, { title = "mermaid" })
		return
	end
	local packs = {}
	if M._cfg.detect_packs then
		packs = utils.detect_icon_packs(src)
	end
	local priority = (opts.priority or M._cfg.run_priority):lower()
	local url = priority == "web" and build_web_url(src) or build_local_url(src, packs)
	vim.fn.setreg("+", url)
	vim.notify("URL copied to + register", vim.log.levels.INFO, { title = "mermaid" })
end

function M.toggle_priority()
	M._cfg.run_priority = (M._cfg.run_priority == "nvim") and "web" or "nvim"
	vim.notify("run_priority → " .. M._cfg.run_priority, vim.log.levels.INFO, { title = "mermaid" })
end

function M.setup(opts)  M._cfg = vim.tbl_deep_extend("force", vim.deepcopy(default_cfg), opts or {})  ensure_html()
end

return M

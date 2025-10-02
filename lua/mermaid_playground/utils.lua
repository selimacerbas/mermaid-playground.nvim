local M = {}

-- Minimal URL-encode (used for icon packs list if needed)
function M.urlencode(str)
	return (str:gsub("[^%w%-%_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- URL-safe base64 without padding (pure Lua) - kept for future use
function M.base64_urlencode(data)
	local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local bytes = { data:byte(1, #data) }
	local pad = (3 - (#bytes % 3)) % 3
	for _ = 1, pad do
		table.insert(bytes, 0)
	end
	local out = {}
	for i = 1, #bytes, 3 do
		local n = bytes[i] * 65536 + bytes[i + 1] * 256 + bytes[i + 2]
		out[#out + 1] = b:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
		out[#out + 1] = b:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
		out[#out + 1] = b:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
		out[#out + 1] = b:sub(n % 64 + 1, n % 64 + 1)
	end
	if pad > 0 then
		out[#out] = "="
	end
	if pad == 2 then
		out[#out - 1] = "="
	end
	local s = table.concat(out)
	s = s:gsub("%+", "-"):gsub("/", "_"):gsub("=", "")
	return s
end

-- Open URL in a browser (macOS, Linux, WSL, Windows)
function M.open_in_browser(url, cmd)
	if cmd and #cmd > 0 then
		vim.fn.jobstart({ cmd, url }, { detach = true })
		return
	end
	if vim.fn.has("mac") == 1 then
		vim.fn.jobstart({ "open", url }, { detach = true })
	elseif vim.fn.has("wsl") == 1 then
		vim.fn.jobstart({ "wslview", url }, { detach = true })
	elseif vim.fn.has("win32") == 1 then
		vim.fn.jobstart({ "cmd", "/c", "start", "", url }, { detach = true })
	else
		vim.fn.jobstart({ "xdg-open", url }, { detach = true })
	end
end

-- Detect Iconify packs: logos:google-cloud -> "logos" (HTML also auto-detects)
function M.detect_icon_packs(src)
	local names, seen = {}, {}
	for p in src:gmatch("%f[%w]([%l%d%-]+):[%l%d%-]+%f[^%w]") do
		if not seen[p] then
			seen[p] = true
			table.insert(names, p)
		end
	end
	return names
end

-- ================= Markdown fenced block extraction =================

-- Helpers
local function ts_text(node, bufnr)
	return node and vim.treesitter.get_node_text(node, bufnr) or nil
end
local function ancestor_of_type(node, wanted)
	while node do
		if node:type() == wanted then
			return node
		end
		node = node:parent()
	end
	return nil
end
local function first_named_child_of_types(node, types)
	if not node then
		return nil
	end
	local n = node:named_child_count()
	for i = 0, n - 1 do
		local c = node:named_child(i)
		if c then
			local ct = c:type()
			for _, t in ipairs(types) do
				if ct == t then
					return c
				end
			end
		end
	end
	return nil
end
local function any_ancestor_is_block_quote(node)
	while node do
		if node:type() == "block_quote" then
			return true
		end
		node = node:parent()
	end
	return false
end

local function node_at_cursor(bufnr)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0)) -- 1-based row
	row = row - 1
	if vim.treesitter.get_node then
		local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
		if ok and node then
			return node
		end
	end
	local okp, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not okp or not parser then
		return nil
	end
	local tree = parser:parse()[1]
	if not tree then
		return nil
	end
	return tree:root():named_descendant_for_range(row, col, row, col)
end

local function try_parsers(bufnr, langs)
	for _, lang in ipairs(langs) do
		local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
		if ok and parser then
			return parser
		end
	end
	return nil
end

-- MAIN: Tree-sitter method (no queries). Works on markdown & mdx.
function M.treesitter_mermaid_under_cursor()
	local bufnr = 0
	local parser = try_parsers(bufnr, { "markdown", "mdx", "markdown_inline" })
	if not parser then
		return false
	end
	parser:parse(true)

	local node = node_at_cursor(bufnr)
	if not node then
		return false
	end

	-- nearest fenced code block
	local block = ancestor_of_type(node, "fenced_code_block")
	if not block then
		return false
	end

	local info = first_named_child_of_types(block, { "info_string", "info" })
	local code = first_named_child_of_types(block, { "code_fence_content", "raw_fence_content" })
	if not code then
		return false
	end

	local info_txt = (ts_text(info, bufnr) or ""):lower()
	if not info_txt:find("mermaid", 1, true) then
		return false
	end

	local src = ts_text(code, bufnr) or ""
	src = src:gsub("^%s+", ""):gsub("%s+$", "")
	if any_ancestor_is_block_quote(block) then
		src = src:gsub("\n>", "\n"):gsub("^>", "")
	end
	if #src == 0 then
		return false
	end
	return true, src
end

-- Regex fallback: case-insensitive; Pandoc attrs; cursor can be on fences
function M.regex_mermaid_under_cursor()
	local cur = vim.api.nvim_win_get_cursor(0)[1] -- 1-based
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local function fence_info(line)
		local fence, rest = (line or ""):match("^%s*([`~]{3,})%s*(.*)$")
		if not fence then
			return nil, false
		end
		rest = rest or ""
		local lower = rest:lower()
		local lang = (rest:match("^([%w%._%-]+)") or ""):lower()
		local ok = (lang == "mermaid") or lower:match("{[^}]*mermaid[^}]*}")
		return fence, ok
	end
	local open_row, fence
	for i = cur, 1, -1 do
		local f, ok = fence_info(lines[i])
		if f then
			if ok then
				open_row, fence = i, f
				break
			else
				return false
			end
		end
	end
	if not open_row then
		return false
	end
	local close_row
	for i = open_row + 1, #lines do
		if (lines[i] or ""):match("^%s*" .. vim.pesc(fence) .. "%s*$") then
			close_row = i
			break
		end
	end
	if not close_row then
		return false
	end
	if cur < open_row or cur > close_row then
		return false
	end
	local body = table.concat(lines, "\n", open_row + 1, close_row - 1)
	body = body:gsub("^%s+", ""):gsub("%s+$", "")
	return #body > 0, body
end

return M

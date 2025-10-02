local M = {}

-- URL encode (minimal)
function M.urlencode(str)
	return (str:gsub("[^%w%-_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- URL-safe base64 (no padding). Pure Lua implementation.
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function to_b64(data)
	return (
		data:gsub(".", function(x)
			return string.format("%02x", string.byte(x))
		end):gsub("%x%x%x?", function(cc)
			return string.char(tonumber(cc, 16))
		end)
	)
end

function M.base64_urlencode(data)
	-- regular base64
	local enc = {}
	local bytes = { data:byte(1, #data) }
	local pad = (3 - (#bytes % 3)) % 3
	for _ = 1, pad do
		table.insert(bytes, 0)
	end
	for i = 1, #bytes, 3 do
		local n = bytes[i] * 65536 + bytes[i + 1] * 256 + bytes[i + 2]
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		enc[#enc + 1] = b64chars:sub(c1 + 1, c1 + 1)
		enc[#enc + 1] = b64chars:sub(c2 + 1, c2 + 1)
		enc[#enc + 1] = b64chars:sub(c3 + 1, c3 + 1)
		enc[#enc + 1] = b64chars:sub(c4 + 1, c4 + 1)
	end
	for _ = 1, pad do
		enc[#enc] = "="
	end
	local out = table.concat(enc)
	-- URL safe + strip padding makes nicer fragments
	out = out:gsub("%+", "-"):gsub("/", "_"):gsub("=+", "")
	return out
end

-- Browser opener (mac, linux, WSL, Windows) with fallback to :! command
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

-- Auto-detect Iconify packs from `pack:icon` occurrences (logos:google-cloud)
function M.detect_icon_packs(src)
	local names = {}
	local seen = {}
	for p in src:gmatch("%f[%w]([%l%d%-]+):[%l%d%-]+%f[^%w]") do
		if not seen[p] then
			seen[p] = true
			table.insert(names, p)
		end
	end
	return names
end

-- Robust: find fenced_code_block ancestor at cursor, then read info/content
local function ts_node_text(node, bufnr)
	return vim.treesitter.get_node_text(node, bufnr)
end

local function parser_markdown(bufnr)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
	if not ok or not parser then
		return nil
	end
	return parser
end

local function node_at_cursor_markdown(bufnr)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0)) -- 1-based row
	row = row - 1
	-- Neovim 0.10+: fast path
	if vim.treesitter.get_node then
		local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col } })
		if ok and node then
			return node
		end
	end
	-- 0.9 fallback
	local parser = parser_markdown(bufnr)
	if not parser then
		return nil
	end
	local tree = parser:parse()[1]
	if not tree then
		return nil
	end
	local root = tree:root()
	return root and root:named_descendant_for_range(row, col, row, col) or nil
end

local function ascend_to(node, type_name)
	while node do
		if node:type() == type_name then
			return node
		end
		node = node:parent()
	end
	return nil
end

-- Query the block itself to get info + content regardless of grammar variants
local function read_block_info_content(block, bufnr, lang)
	lang = lang or "markdown"
	local q = vim.treesitter.query.parse(
		lang,
		[[
    (fenced_code_block
      (info_string)? @info
      (info)?         @info
      (code_fence_content)? @content
      (raw_fence_content)?  @content
    ) @block
  ]]
	)
	for _, match in q:iter_matches(block, bufnr, block:start(), block:end_()) do
		local info, content
		for id, node in pairs(match) do
			local name = q.captures[id]
			if name == "info" then
				info = node
			end
			if name == "content" then
				content = node
			end
		end
		local info_text = info and ts_node_text(info, bufnr) or ""
		local content_text = content and ts_node_text(content, bufnr) or ""
		return info_text, content_text
	end
	return "", ""
end

function M.treesitter_mermaid_under_cursor()
	local bufnr = 0
	local node = node_at_cursor_markdown(bufnr)
	if not node then
		return false
	end
	local block = ascend_to(node, "fenced_code_block")
	if not block then
		return false
	end

	local info_text, body = read_block_info_content(block, bufnr, "markdown")
	local info = (info_text or ""):lower()
	-- accept: ```mermaid, ``` mermaid, ```{.mermaid}, ```{class="mermaid"} ...
	local is_mermaid = info:find("mermaid", 1, true) ~= nil
	if not is_mermaid then
		return false
	end

	body = (body or ""):gsub("^%s+", ""):gsub("%s+$", "")
	return #body > 0, body
end

-- Regex fallback (case-insensitive + Pandoc-style + allow cursor on fences)
function M.regex_mermaid_under_cursor()
	local cur_row = vim.api.nvim_win_get_cursor(0)[1] -- 1-based
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	local function fence_info(line)
		local fence, rest = line:match("^%s*([`~]{3,})%s*(.*)$")
		if not fence then
			return nil, false
		end
		rest = rest or ""
		local lower = rest:lower()
		-- plain language or pandoc/attrs with mermaid inside
		local lang = (rest:match("^([%w%._%-]+)") or ""):lower()
		local ok = lang == "mermaid" or lower:match("{[^}]*mermaid[^}]*}")
		return fence, ok
	end

	-- find the nearest opening fence at/above cursor that is mermaid
	local open_row, open_fence
	for i = cur_row, 1, -1 do
		local f, ok = fence_info(lines[i] or "")
		if f then
			if ok then
				open_row, open_fence = i, f
				break
			else
				return false
			end
		end
	end
	if not open_row then
		return false
	end

	-- find its closing fence
	local close_row
	for i = open_row + 1, #lines do
		if (lines[i] or ""):match("^%s*" .. vim.pesc(open_fence) .. "%s*$") then
			close_row = i
			break
		end
	end
	if not close_row then
		return false
	end

	-- allow cursor on either fence or inside
	if cur_row < open_row or cur_row > close_row then
		return false
	end

	local body = table.concat(lines, "\n", open_row + 1, close_row - 1)
	body = body:gsub("^%s+", ""):gsub("%s+$", "")
	return #body > 0, body
end

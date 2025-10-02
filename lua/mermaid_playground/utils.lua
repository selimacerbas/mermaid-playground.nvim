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

-- ===== Markdown fenced block extraction =====
local function ts_node_text(node, bufnr)
	return vim.treesitter.get_node_text(node, bufnr)
end

-- Treesitter path: allow cursor on fences too
function M.treesitter_mermaid_under_cursor()
	local bufnr = 0
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
	if not ok or not parser then
		ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown_inline")
		if not ok or not parser then
			return false
		end
	end
	local tree = parser:parse()[1]
	if not tree then
		return false
	end
	local root = tree:root()

	local qstr = [[
    (fenced_code_block (info_string) @info (code_fence_content) @content) @block
    (fenced_code_block (info) @info (code_fence_content) @content) @block
    (fenced_code_block (info_string) @info (raw_fence_content) @content) @block
  ]]
	local okq, query = pcall(vim.treesitter.query.parse, parser:lang(), qstr)
	if not okq then
		return false
	end

	local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
	for _, match, _ in query:iter_matches(root, bufnr, 0, -1) do
		local block, info, content
		for id, node in pairs(match) do
			local name = query.captures[id]
			if name == "block" then
				block = node
			end
			if name == "info" then
				info = node
			end
			if name == "content" then
				content = node
			end
		end
		if block and info and content then
			local sr, _, er, _ = block:range()
			if row >= sr and row <= er then -- <= inclusive: allow fence lines
				local lang = (vim.treesitter.get_node_text(info, bufnr) or ""):gsub("^%s+", ""):gsub("%s+$", "")
				lang = lang:lower()
				if lang == "mermaid" or lang:match("%f[%w]mermaid%f[%W]") then
					local txt = vim.treesitter.get_node_text(content, bufnr)
					txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
					return true, txt
				end
			end
		end
	end
	return false
end

-- Regex fallback: case-insensitive + Pandoc-style + allow fence line
function M.regex_mermaid_under_cursor()
	local row = vim.api.nvim_win_get_cursor(0)[1] -- 1-based
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	local function mermaid_fence(line)
		-- capture fence (``` or ~~~) and the rest of the info string (anything)
		local fence, rest = line:match("^%s*([`~]{3,})%s*(.*)$")
		if not fence then
			return nil, false
		end
		rest = rest or ""
		local lang = (rest:match("^([%w%._%-]+)") or ""):lower()
		local is_mermaid = (lang == "mermaid") or rest:lower():match("{[^}]*mermaid[^}]*}")
		return fence, is_mermaid
	end

	-- find opening mermaid fence at/above cursor
	local open_row, open_fence
	for i = row, 1, -1 do
		local f, ok = mermaid_fence(lines[i] or "")
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

	-- find matching closing fence below
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

	-- allow cursor on fence lines or inside
	if row < open_row or row > close_row then
		return false
	end

	local body = table.concat(lines, "\n", open_row + 1, close_row - 1)
	return true, body
end

return M

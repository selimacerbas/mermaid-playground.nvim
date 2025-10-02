local M = {}

-- Minimal URL-encode
function M.urlencode(str)
	return (str:gsub("[^%w%-%_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- URL-safe base64 without padding (pure Lua, no deps)
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
	-- add "=" padding then strip for URL-safety
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

-- Detect Iconify packs: logos:google-cloud -> "logos"
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

-- Tree-sitter detection aligned with diagram.nvim: iterate fenced blocks,
-- pick the block whose range covers the cursor; accept Pandoc-style fences.
function M.treesitter_mermaid_under_cursor()
	local bufnr = 0
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
	if not ok or not parser then
		return false
	end
	parser:parse(true)
	local tree = parser:parse()[1]
	if not tree then
		return false
	end
	local root = tree:root()

	local ts_query = require("vim.treesitter.query")
	local query = ts_query.parse(
		"markdown",
		[[
    (fenced_code_block (info_string) @info (code_fence_content) @code) @block
    (fenced_code_block (info)         @info (code_fence_content) @code) @block
    (fenced_code_block (info_string) @info (raw_fence_content)   @code) @block
  ]]
	)

	local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
	local ts_text = vim.treesitter.get_node_text

	for _, match, _ in query:iter_matches(root, bufnr, 0, -1) do
		local block, info, code
		for id, node in pairs(match) do
			local cap = query.captures[id]
			if cap == "block" then
				block = node
			elseif cap == "info" then
				info = node
			elseif cap == "code" then
				code = node
			end
		end
		if block and info and code then
			local sr, _, er, _ = block:range()
			-- allow cursor on fence lines or inside block
			if row >= sr and row <= er then
				local info_txt = (ts_text(info, bufnr) or ""):lower()
				-- accept plain lang or Pandoc attrs containing "mermaid"
				if info_txt:find("mermaid", 1, true) then
					local src = ts_text(code, bufnr) or ""
					src = src:gsub("^%s+", ""):gsub("%s+$", "")
					-- if block is inside a block_quote, unquote like diagram.nvim does
					local p = block:parent()
					local gp = p and p:parent() or nil
					if (p and p:type() == "block_quote") or (gp and gp:type() == "block_quote") then
						src = src:gsub("\n>", "\n"):gsub("^>", "")
					end
					return true, src
				end
			end
		end
	end
	return false
end

-- Regex fallback: case-insensitive; supports Pandoc attrs; cursor can be on fence lines
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

	-- find opening mermaid fence at/above cursor
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

	-- find matching closing fence
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

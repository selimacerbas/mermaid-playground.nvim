local M = {}

-- Minimal URL-encode
function M.urlencode(str)
	return (str:gsub("[^%w%-%_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- URL-safe base64 without padding (pure Lua)
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

-- Helpers
local function ts_text(node, bufnr)
	return vim.treesitter.get_node_text(node, bufnr)
end
local function named_child_by_type(node, t)
	if not node then
		return nil
	end
	local n = node:named_child_count()
	for i = 0, n - 1 do
		local c = node:named_child(i)
		if c and c:type() == t then
			return c
		end
	end
	return nil
end

-- Query builder with safe fallbacks (no unsupported node types)
local function get_queries(lang)
	local ts_query = require("vim.treesitter.query")
	-- 1) Preferred: explicitly capture info_string + code_fence_content
	local ok1, q1 = pcall(
		ts_query.parse,
		lang,
		[[
    (fenced_code_block (info_string) @info (code_fence_content) @code) @block
  ]]
	)
	-- 2) Fallback: capture blocks only, we’ll search children in Lua  local ok2, q2 = pcall(
l(ts_query.parse,
, lang,
, [[
    (fenced_code_block) @block
  ]]]])  return (ok1 and q1 or nil), (ok2 and q2 or nil)
end

-- Tree-sitter detection (robust): iterate fenced blocks and pick the one under the cursor.
function M.treesitter_mermaid_under_cursor()  local bufnr = 0  local okp, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")  if not okp or not parser then
n return falsee end
  parser:parse(true)  local tree = parser:parse()[1]  if not tree then
n return falsee end  local root = tree:root()
  local q_exact, q_blocks = get_queries("markdown")  local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
  local function consider_block(block, info_node, code_node)
  -- If info/code nodes are not provided (block-only query), find them.
  if not info_node then
	n info_node = named_child_by_type(block, "info_string")
) end
  if not code_node then
	n code_node = named_child_by_type(block, "code_fence_content")
) end
  if not code_node then
	n return nil
l end

  local sr, _, er, _ = block:range()
  if not (row >= sr and row <= er) then
	n return nil
l end -- allow fence lines too

  local info_txt = (info_node and ts_text(info_node, bufnr) or ""):lower()
  -- Accept plain "mermaid" OR Pandoc/attr style containing "mermaid"
  if not info_txt:find("mermaid", 1, true) then
	n return nil
l end

  local src = ts_text(code_node, bufnr) or ""
  src = src:gsub("^%s+", ""):gsub("%s+$", "")

  -- Unquote if inside block_quote (behavior like diagram.nvim)
  local p = block:parent()
; local gp = p and p:parent() or nil
  if (p and p:type() == "block_quote") or (gp and gp:type() == "block_quote") then
	  src = src:gsub("\n>", "\n"):gsub("^>", "")
  end
  return src  end
  -- Try the exact query first  if q_exact then
  for _, match, _ in q_exact:iter_matches(root, bufnr, 0, -1) do
	  local block, info, code
	  for id, node in pairs(match) do
		  local cap = q_exact.captures[id]
		  if cap == "block" then
			  block = node
		  elseif cap == "info" then
			  info = node
		  elseif cap == "code" then
			  code = node
		  end
	  end
	  local src = block and consider_block(block, info, code)
	  if src and #src > 0 then
		n return true, src
	c end
  end  end
  -- Fallback: block-only query and manual child discovery  if q_blocks then
  for _, match, _ in q_blocks:iter_matches(root, bufnr, 0, -1) do
	  local block = match[1]
	  local src = block and consider_block(block, nil, nil)
	  if src and #src > 0 then
		n return true, src
	c end
  end  end
  return false
end

-- Regex fallback: case-insensitive; supports Pandoc attrs; cursor can be on fence lines
function M.regex_mermaid_under_cursor()  local cur = vim.api.nvim_win_get_cursor(0)[1] -- 1-based  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local function fence_info(line)
  local fence, rest = (line or ""):match("^%s*([`~]{3,})%s*(.*)$")
  if not fence then
	n return nil, false
e end
  rest = rest or ""
  local lower = rest:lower()
  local lang = (rest:match("^([%w%._%-]+)") or ""):lower()
  local ok = (lang == "mermaid") or lower:match("{[^}]*mermaid[^}]*}")
  return fence, ok  end
  -- find opening mermaid fence at/above cursor  local open_row, fence  for i = cur, 1, -1 do
  local f, ok = fence_info(lines[i])
  if f then
	  if ok then
		  open_row, fence = i, f
		; break
	  else
		e return false
	e end
  end  end  if not open_row then
n return falsee end
  -- find matching closing fence  local close_row  for i = open_row + 1, #lines do
  if (lines[i] or ""):match("^%s*" .. vim.pesc(fence) .. "%s*$") then
	  close_row = i
	; break
  end  end  if not close_row then
n return falsee end
  -- allow cursor on fence lines or inside  if cur < open_row or cur > close_row then
n return falsee end
  local body = table.concat(lines, "\n", open_row + 1, close_row - 1)  body = body:gsub("^%s+", ""):gsub("%s+$", "")  return #body > 0, body
end

return M

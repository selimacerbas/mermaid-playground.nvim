local M = {}

local function ts_get_node_text(node, bufnr)
	if vim.treesitter.get_node_text then
		return vim.treesitter.get_node_text(node, bufnr)
	else
		return require("nvim-treesitter.ts_utils").get_node_text(node, bufnr)
	end
end

local function cursor_in_node(node, row, col)
	local sr, sc, er, ec = node:range()
	if row < sr or row > er then
		return false
	end
	if row == sr and col < sc then
		return false
	end
	if row == er and col > ec then
		return false
	end
	return true
end

--- Extract mermaid fenced block content under cursor using Tree-sitter.
---@param bufnr integer
---@return boolean ok, string|nil code_or_err
function M.get_mermaid_block_under_cursor(bufnr)
	bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()

	local ft = vim.bo[bufnr].filetype
	if ft ~= "markdown" and ft ~= "mdx" then
		-- Try anyway but warn
		-- return false, "buffer is not markdown"
	end

	local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
	if not ok_parser or not parser then
		return M._fallback_scan(bufnr)
	end

	local tree = parser:parse()[1]
	if not tree then
		return M._fallback_scan(bufnr)
	end
	local root = tree:root()

	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	row = row - 1 -- 0-indexed

	local query = vim.treesitter.query.parse(
		"markdown",
		[[
    (fenced_code_block
      (info_string) @info
      (code_fence_content) @content
    ) @block
  ]]
	)

	local best
	for _, match, _ in query:iter_matches(root, bufnr) do
		local info_node, content_node, block_node
		for id, node in pairs(match) do
			local name = query.captures[id]
			if name == "info" then
				info_node = node
			end
			if name == "content" then
				content_node = node
			end
			if name == "block" then
				block_node = node
			end
		end
		if info_node and content_node and block_node then
			local info_text = ts_get_node_text(info_node, bufnr) or ""
			-- info_string may include extra words, we only need it to start with mermaid
			if info_text:match("^%s*mermaid[%s%c%p]*") then
				if cursor_in_node(block_node, row, col) then
					local content = ts_get_node_text(content_node, bufnr) or ""
					return true, content
				end
				-- keep closest block if none under cursor (optional)
				best = best or content_node
			end
		end
	end

	if best then
		return true, ts_get_node_text(best, bufnr) or ""
	end

	-- Fallback to textual scan
	return M._fallback_scan(bufnr)
end

-- Plain text fallback when Tree-sitter is missing
function M._fallback_scan(bufnr)
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local function is_fence(line)
		return line:match("^%s*```+") or line:match("^%s*~~~+")
	end

	-- Search upward for opening fence labelled mermaid
	local open_idx
	for i = row, 1, -1 do
		local l = lines[i]
		if is_fence(l) then
			if l:lower():match("mermaid") then
				open_idx = i
				break
			else
				return false, "cursor not inside a mermaid code fence"
			end
		end
	end
	if not open_idx then
		return false, "no opening mermaid fence found above cursor"
	end

	-- Search downward for closing fence
	local close_idx
	for i = open_idx + 1, #lines do
		if is_fence(lines[i]) then
			close_idx = i
			break
		end
	end
	if not close_idx then
		return false, "no closing fence found for mermaid block"
	end

	local content = table.concat({ unpack(lines, open_idx + 1, close_idx - 1) }, "\n")
	return true, content
end

return M

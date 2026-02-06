local M = {}

local function get_node_text(node, bufnr)
	return vim.treesitter.get_node_text(node, bufnr)
end

---Extracts the mermaid fenced code block covering the cursor using Tree-sitter.
---@param bufnr integer
---@return string|nil
function M.extract_under_cursor(bufnr)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
	if not ok then
		error("No Tree-sitter parser for markdown")
	end
	local tree = parser:parse()[1]
	local root = tree:root()

	local query = vim.treesitter.query.parse(
		"markdown",
		[[
    (fenced_code_block
      (info_string) @info
      (code_fence_content) @content)
  ]]
	)

	local cursor = vim.api.nvim_win_get_cursor(0)
	local cur_row = cursor[1] - 1

	for id, nodes, _ in query:iter_matches(root, bufnr, 0, -1) do
		-- nodes[1] = info, nodes[2] = content (thanks to query order)
		local info = nodes[1]
		local content = nodes[2]
		local block = info:parent()
		local srow, _, erow, _ = block:range()
		if cur_row >= srow and cur_row <= erow then
			local info_txt = get_node_text(info, bufnr):lower()
			if info_txt:match("mermaid") then
				return get_node_text(content, bufnr)
			end
		end
	end
	error("Cursor is not inside a mermaid fenced code block")
end

-- Fallback: simple regex scan for the nearest mermaid block above the cursor
function M.fallback_scan(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local i = row
	-- search upwards for ```mermaid
	while i >= 1 do
		if lines[i]:match("^%s*```%s*mermaid") then
			break
		end
		i = i - 1
	end
	if i < 1 then
		return nil
	end
	i = i + 1
	local acc = {}
	while i <= #lines and not lines[i]:match("^%s*```%s*$") do
		table.insert(acc, lines[i])
		i = i + 1
	end
	return table.concat(acc, "\n")
end

return M

local M = {}

local function parser_for(bufnr)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown", {})
	if not ok then
		ok, parser = pcall(vim.treesitter.get_parser, bufnr, "mdx", {})
	end
	if not ok then
		error("Install nvim-treesitter 'markdown' (or 'mdx') parser.")
	end
	return parser
end

function M.code_at_cursor(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	row = row - 1
	local tree = parser_for(bufnr):parse()[1]
	local root = tree:root()
	local node = root:named_descendant_for_range(row, col, row, col)

	while node and node:type() ~= "fenced_code_block" do
		node = node:parent()
	end
	if not node then
		return nil, "Cursor is not inside a fenced code block."
	end

	local lang, content
	for child in node:iter_children() do
		local t = child:type()
		if t == "info_string" then
			local s = (vim.treesitter.get_node_text(child, bufnr) or ""):gsub("^%s*", ""):gsub("%s*$", "")
			lang = s:match("^([%w%-%_]+)")
		elseif t == "code_fence_content" then
			content = vim.treesitter.get_node_text(child, bufnr) or ""
		end
	end

	if (lang or ""):lower() ~= "mermaid" then
		return nil, ("Code fence is '%s', not 'mermaid'."):format(lang or "unknown")
	end
	if not content or content == "" then
		return nil, "Mermaid block is empty."
	end
	return content
end

return M

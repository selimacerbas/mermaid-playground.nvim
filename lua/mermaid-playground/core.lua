local M = {}

local config = {
	template_path = vim.fn.stdpath("config") .. "/lua/selimacerbas/mermaid-playground.nvim/assets/template.html",
	placeholder = "%%MERMAID_CODE%%",
}

-- Finds the 'mermaid' code block under the cursor
function M.find_mermaid_block()
	local bufnr = vim.api.nvim_get_current_buf()
	local winnr = vim.api.nvim_get_current_win()
	local pos = vim.api.nvim_win_get_cursor(winnr)

	-- Ensure markdown treesitter parser is available
	if not vim.treesitter.get_parser(bufnr, "markdown") then
		vim.notify("Markdown treesitter parser not found. Please install it.", vim.log.levels.ERROR)
		return nil
	end

	local root = vim.treesitter.get_parser(bufnr):parse()[1]:root()
	local node = root:descendant_for_range(pos[1] - 1, pos[2], pos[1] - 1, pos[2])

	-- Traverse up to find the code block
	while node do
		if node:type() == "fenced_code_block" then
			-- Query to find the language node and check if it's 'mermaid'
			local query = vim.treesitter.query.parse("markdown", "((info_string) @lang)")
			for _, captures, _ in query:iter_captures(node, bufnr) do
				local lang_node = captures[1]
				local lang_text = vim.treesitter.get_node_text(lang_node, bufnr)
				if lang_text == "mermaid" then
					-- Get the content of the code block
					local content_node = node:child(1) -- The code content is usually the second child
					if content_node:type() == "code_fence_content" then
						return vim.treesitter.get_node_text(content_node, bufnr)
					end
				end
			end
			-- If we found a code block but it's not mermaid, stop searching up.
			return nil
		end
		node = node:parent()
	end

	return nil
end

-- Reads the template and injects the mermaid code
function M.prepare_html(mermaid_code)
	local file = io.open(config.template_path, "r")
	if not file then
		vim.notify("Could not open HTML template at: " .. config.template_path, vim.log.levels.ERROR)
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content:gsub(config.placeholder, mermaid_code)
end

return M

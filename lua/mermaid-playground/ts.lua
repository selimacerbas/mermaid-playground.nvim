local M = {}

-- Try Tree-sitter first; fall back to a regex scan.
-- Returns {start_lnum, end_lnum, lang} (1-based, inclusive), or nil
function M.find_fence_under_cursor(bufnr)
	bufnr = bufnr or 0
	local cur = vim.api.nvim_win_get_cursor(0) -- {lnum, col}
	local row = cur[1] - 1 -- 0-based for TS

	-- --- Tree-sitter path ---
	local ok, ts = pcall(require, "vim.treesitter")
	if ok then
		local okp, parser = pcall(ts.get_parser, bufnr, "markdown")
		if okp and parser then
			local trees = parser:parse()
			if trees and trees[1] then
				local root = trees[1]:root()
				local query = ts.query.parse(
					"markdown",
					[[
          (fenced_code_block
            (info_string)? @info) @block
        ]]
				)

				for _, matches, _ in query:iter_matches(root, bufnr, 0, -1) do
					local block = matches[query.captures["block"]]
					if block then
						local sr, _, er, _ = block:range() -- 0-based, end-exclusive col
						if row >= sr and row <= er then
							-- Try to extract language from the info_string
							local info = matches[query.captures["info"]]
							local lang = nil
							if info then
								local text = vim.treesitter.get_node_text(info, bufnr) or ""
								-- info_string often like: "```mermaid" or "``` mermaid { init: ... }"
								lang = text:match("[`~]+%s*([%w_-]+)") or text:match("{%s*([%w_-]+)")
							end
							-- Trim the surrounding fences from line range
							local start_lnum = sr + 2 -- 1-based: skip opening fence line
							local end_lnum = er -- 1-based: er is fence end line already (TS range end is exclusive by col, but line is inclusive)
							-- Guard: if empty block, allow anyway (viewer will say empty)
							return { start_lnum, end_lnum, (lang or ""):lower() }
						end
					end
				end
			end
		end
	end

	-- --- Fallback scan (supports up to 3 leading spaces) ---
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local i = row
	local opener_pat = "^%s*([`~]{3,})%s*([%w_-]+)?"
	while i >= 0 do
		local line = lines[i + 1] or ""
		local fence, lang = line:match(opener_pat)
		if fence then
			-- found an opener, now search downward for matching fence char
			local j = i + 1
			local closer_pat = "^%s*" .. vim.pesc(fence) .. "%s*$"
			while j < #lines do
				if lines[j + 1]:match(closer_pat) then
					if row >= i and row <= j then
						local l = (lang or ""):lower()
						return { i + 2, j, l } -- content between fences
					else
						break
					end
				end
				j = j + 1
			end
		end
		i = i - 1
	end

	return nil
end

return M

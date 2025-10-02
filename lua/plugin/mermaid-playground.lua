local core = require("mermaid-playground.core")
local server = require("mermaid-playground.server")

local function render_current_block()
	local mermaid_code = core.find_mermaid_block()
	if not mermaid_code or mermaid_code == "" then
		vim.notify("No Mermaid code block found under cursor.", vim.log.levels.WARN)
		return
	end

	local html_content = core.prepare_html(mermaid_code)
	if not html_content then
		return -- Error message already shown by prepare_html
	end

	server.render(html_content)
end

vim.api.nvim_create_user_command("MermaidPlayground", render_current_block, {
	desc = "Render the Mermaid diagram under the cursor in a browser",
})

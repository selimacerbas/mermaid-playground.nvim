local M = {}

local server_job_id = nil
local port = 4070
local temp_dir = vim.fn.stdpath("cache") .. "/mermaid-playground"

-- Create temporary directory if it doesn't exist
vim.fn.mkdir(temp_dir, "p")

-- Starts a simple Python web server
function M.start()
	if server_job_id and vim.fn.jobwait({ server_job_id }, 0)[1] == -1 then
		-- Server is already running
		return true
	end

	local command
	if vim.fn.executable("python3") then
		command = "python3"
	elseif vim.fn.executable("python") then
		command = "python"
	else
		vim.notify("Python is required to run the web server.", vim.log.levels.ERROR)
		return false
	end

	server_job_id = vim.fn.jobstart({
		command,
		"-m",
		"http.server",
		tostring(port),
		"--directory",
		temp_dir,
	}, {
		-- Detach the process so it keeps running
		detach = true,
		-- Hide stdout/stderr for a cleaner experience
		stdout_buffered = true,
		stderr_buffered = true,
	})

	if server_job_id <= 0 then
		vim.notify("Failed to start web server.", vim.log.levels.ERROR)
		server_job_id = nil
		return false
	end

	vim.notify("Mermaid server started at http://localhost:" .. port)
	-- Give the server a moment to start up
	vim.defer_fn(function() end, 200)
	return true
end

-- Writes content to index.html and opens it in the browser
function M.render(html_content)
	if not M.start() then
		return
	end

	local index_file = temp_dir .. "/index.html"
	local file = io.open(index_file, "w")
	if not file then
		vim.notify("Failed to write temporary HTML file.", vim.log.levels.ERROR)
		return
	end
	file:write(html_content)
	file:close()

	local url = "http://localhost:" .. port
	local open_cmd
	local os = vim.loop.os_uname().sysname
	if os == "Darwin" then
		open_cmd = "open"
	elseif os == "Linux" then
		open_cmd = "xdg-open"
	elseif os:match("Windows") then
		open_cmd = "start"
	else
		vim.notify("Unsupported OS for opening browser.", vim.log.levels.WARN)
		return
	end

	vim.fn.jobstart({ open_cmd, url }, { detach = true })
end

return M

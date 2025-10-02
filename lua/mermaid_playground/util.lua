local M = {}

function M.join(...)
	local sep = package.config:sub(1, 1)
	local out = table.concat({ ... }, sep)
	return out
end

function M.ensure_dir(path)
	if vim.fn.isdirectory(path) == 0 then
		vim.fn.mkdir(path, "p")
	end
end

function M.write_file(path, content)
	local f = assert(io.open(path, "wb"))
	f:write(content or "")
	f:close()
end

function M.read_file(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local d = f:read("*a")
	f:close()
	return d
end

function M.copy_if_missing(src, dst)
	local dir = vim.fn.fnamemodify(dst, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	if vim.fn.filereadable(dst) == 1 then
		return true
	end
	local data = M.read_file(src)
	if not data then
		return false, "Source not readable: " .. src
	end
	M.write_file(dst, data)
	return true
end

function M.open_url(url)
	if vim.ui and vim.ui.open then
		pcall(vim.ui.open, url) -- nvim 0.10+
		return
	end
	local cmd
	if vim.fn.has("mac") == 1 then
		cmd = { "open", url }
	elseif vim.fn.has("win32") == 1 then
		cmd = { "cmd", "/c", "start", "", url }
	else
		cmd = { "xdg-open", url }
	end
	vim.fn.jobstart(cmd, { detach = true })
end

return M

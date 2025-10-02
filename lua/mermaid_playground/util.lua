local M = {}

function M.mkdirp(path)
	if vim.fn.isdirectory(path) == 0 then
		vim.fn.mkdir(path, "p")
	end
end

function M.file_exists(path)
	local stat = vim.loop.fs_stat(path)
	return stat and stat.type == "file"
end

function M.write_text(path, text)
	local fd = assert(vim.loop.fs_open(path, "w", 420)) -- 0644
	assert(vim.loop.fs_write(fd, text, 0))
	assert(vim.loop.fs_close(fd))
end

function M.read_text(path)
	local fd = assert(vim.loop.fs_open(path, "r", 420))
	local stat = assert(vim.loop.fs_fstat(fd))
	local data = assert(vim.loop.fs_read(fd, stat.size, 0))
	assert(vim.loop.fs_close(fd))
	return data
end

function M.copy_file(src, dst)
	local data = M.read_text(src)
	M.write_text(dst, data)
end

function M.resolve_asset(rel)
	-- Resolve to this plugin’s root based on this file location  local info = debug.getinfo(1, "S')  local this = info.source:sub(2) -- strip '@'  local root = this:match('(.-)/lua/mermaid_playground/util%.lua$')  return root .. "/' .. rel
end

function M.open_in_browser(url)  local cmd  if vim.fn.has('mac') == 1 then
  cmd = { 'open', url }  elseif vim.fn.has('unix') == 1 then
  cmd = { 'xdg-open', url }  elseif vim.fn.has('win32') == 1 then
  cmd = { 'cmd.exe', '/c', 'start', url }  end  if cmd then
  vim.fn.jobstart(cmd, { detach = true })  end
end

return M

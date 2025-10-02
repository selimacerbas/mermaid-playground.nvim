local uv = vim.loop
local util = require("mermaid_playground.util")

local M = { _srv = nil, _port = nil, _root = nil }

local function mime(p)
	if p:match("%.html$") then
		return "text/html; charset=utf-8"
	end
	if p:match("%.mmd$") then
		return "text/plain; charset=utf-8"
	end
	if p:match("%.svg$") then
		return "image/svg+xml"
	end
	if p:match("%.txt$") then
		return "text/plain; charset=utf-8"
	end
	if p:match("%.ico$") then
		return "image/x-icon"
	end
	return "application/octet-stream"
end

local function send(sock, code, body, ctype)
	local status = code == 200 and "OK" or "Not Found"
	local hdr = table.concat({
		("HTTP/1.1 %d %s"):format(code, status),
		"Cache-Control: no-store",
		"Content-Type: " .. (ctype or "text/plain"),
		"Content-Length: " .. tostring(#body),
		"",
		"",
	}, "\r\n")
	sock:write(hdr .. body)
end

local function safe_join(root, req)
	if req == "/" then
		req = "/index.html"
	end
	if not req:match("^/[0-9A-Za-z%._%-%/]+$") then
		return nil
	end
	return util.join(root, req:gsub("^/", ""))
end

local function handle(client, root)
	local buf = ""
	client:read_start(function(err, chunk)
		if err then
			return
		end
		if not chunk then
			return
		end
		buf = buf + chunk
	end)
	client:read_start(function(err, chunk)
		if err or not chunk then
			return
		end
		buf = buf .. chunk
		if buf:find("\r\n\r\n", 1, true) then
			local method, path = buf:match("^(%u+)%s+([^%s]+)")
			if method ~= "GET" then
				send(client, 404, "")
				client:close()
				return
			end
			if path == "/health" then
				send(client, 200, "ok", "text/plain")
				client:close()
				return
			end
			local full = safe_join(root, path)
			if not full or vim.fn.filereadable(full) == 0 then
				send(client, 404, "Not Found")
				client:close()
				return
			end
			local body = util.read_file(full) or ""
			send(client, 200, body, mime(full))
			client:close()
		end
	end)
end

function M.ensure(root, port)
	if M._srv and M._port == port and M._root == root then
		return true
	end
	local srv = uv.new_tcp()
	srv:setoption("reuseaddr", true)
	local ok, err = srv:bind("127.0.0.1", port)
	if not ok then
		return true
	end -- assume something already serves it
	local ok2 = srv:listen(128, function()
		local c = uv.new_tcp()
		srv:accept(c)
		handle(c, root)
	end)
	if not ok2 then
		pcall(srv.close, srv)
		return false
	end
	M._srv, M._port, M._root = srv, port, root
	return true
end

function M.shutdown()
	if M._srv then
		pcall(M._srv.close, M._srv)
		M._srv = nil
	end
end

return M

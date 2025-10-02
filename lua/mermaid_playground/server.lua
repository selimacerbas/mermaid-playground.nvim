-- lua/mermaid_playground/server.lua
local uv = vim.uv or vim.loop
local util = require("mermaid_playground.util")

local M = { _srv = nil, _port = nil, _root = nil }

local function mime_for(path)
	if path:match("%.html$") then
		return "text/html; charset=utf-8"
	end
	if path:match("%.mmd$") then
		return "text/plain; charset=utf-8"
	end
	if path:match("%.svg$") then
		return "image/svg+xml"
	end
	if path:match("%.txt$") then
		return "text/plain; charset=utf-8"
	end
	if path:match("%.ico$") then
		return "image/x-icon"
	end
	return "application/octet-stream"
end

local function send(sock, code, body, ctype)
	local status = (code == 200) and "OK" or (code == 404 and "Not Found" or "Error")
	local hdr = table.concat({
		("HTTP/1.1 %d %s"):format(code, status),
		"Cache-Control: no-store",
		"Content-Type: " .. (ctype or "text/plain; charset=utf-8"),
		"Content-Length: " .. tostring(#body),
		"",
		"",
	}, "\r\n")
	sock:write(hdr .. body)
end

local function sanitize_request_path(req_path)
	local p = (req_path or "/"):match("^[^%?#]+") or "/" -- strip ?query and #fragment
	if p == "/" then
		p = "/index.html"
	end
	-- URL-decode %xx
	p = p:gsub("%%(%x%x)", function(h)
		local n = tonumber(h, 16)
		if not n then
			return ""
		end
		return string.char(n)
	end)
	-- allow only simple safe paths
	if not p:match("^/[0-9A-Za-z%._%-%/]+$") then
		return nil
	end
	return p
end

local function resolve_path(root, req_path)
	local p = sanitize_request_path(req_path)
	if not p then
		return nil
	end
	return util.join(root, p:gsub("^/", ""))
end

local function handle_client(client, root)
	local buf = ""
	client:read_start(function(err, chunk)
		if err then
			pcall(client.close, client)
			return
		end
		if not chunk then
			return
		end
		buf = buf .. chunk
		if buf:find("\r\n\r\n", 1, true) then
			local method, path = buf:match("^(%u+)%s+([^%s]+)")
			if method ~= "GET" or not path then
				send(client, 404, "Not Found")
				client:shutdown(function()
					pcall(client.close, client)
				end)
				return
			end

			if path == "/health" or path:match("^/health[%?#]") then
				send(client, 200, "ok", "text/plain; charset=utf-8")
				client:shutdown(function()
					pcall(client.close, client)
				end)
				return
			end

			local full = resolve_path(root, path)
			if not full or vim.fn.filereadable(full) == 0 then
				send(client, 404, "Not Found")
				client:shutdown(function()
					pcall(client.close, client)
				end)
				return
			end

			local body = util.read_file(full) or ""
			send(client, 200, body, mime_for(full))
			client:shutdown(function()
				pcall(client.close, client)
			end)
		end
	end)
end

local function try_bind(host, port)
	local srv = uv.new_tcp()
	local ok, err = pcall(srv.bind, srv, host, port)
	if not ok then
		pcall(srv.close, srv)
		return nil, err
	end
	return srv
end

function M.is_running()
	return M._srv ~= nil
end

function M.ensure(root, port)
	if M._srv and M._port == port and M._root == root then
		return true
	end
	local srv, err = try_bind("127.0.0.1", port)
	if not srv then
		-- Port already in use — assume something is serving the folder.
  M._srv, M._port, M._root = nil, port, root
  return true  end  local ok, listen_err = pcall(srv.listen, srv, 128, function()
  local client = uv.new_tcp()
  srv:accept(client)
  handle_client(client, root)  end)  if not ok then
  pcall(srv.close, srv)
  return false, listen_err  end  M._srv, M._port, M._root = srv, port, root  return true
end

function M.shutdown()  if M._srv then
  pcall(M._srv.close, M._srv)
; M._srv = nil  end
end

return M

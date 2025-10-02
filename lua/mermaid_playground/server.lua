-- Tiny HTTP server (luv) that serves index.html and current.mmd on localhost
local uv = vim.loop

local M = {
  _server = nil,
  _root   = nil,
  _port   = nil,
}

local function http_date()
  return os.date("!%a, %d %b %Y %H:%M:%S GMT")
end

local function read_file(path)
  local fd = io.open(path, "rb")
  if not fd then return nil end
  local data = fd:read("*a")
  fd:close()
  return data
end

local function mime_for(path)
  if path:match("%.html?$") then return "text/html; charset=utf-8" end
  if path:match("%.mmd$")  then return "text/plain; charset=utf-8" end
  if path:match("%.json$") then return "application/json; charset=utf-8" end
  if path:match("%.svg$")  then return "image/svg+xml" end
  if path:match("%.css$")  then return "text/css; charset=utf-8" end
  if path:match("%.js$")   then return "text/javascript; charset=utf-8" end
  return "text/plain; charset=utf-8"
end

local function write_response(client, status, headers, body)
  local reason = ({
    [200]="OK",[204]="No Content",[304]="Not Modified",
    [400]="Bad Request",[404]="Not Found",[405]="Method Not Allowed",
    [500]="Internal Server Error"
  })[status] or "OK"
  headers = headers or {}
  headers["Date"] = http_date()
  headers["Server"] = "mermaid-playground.nvim"
  headers["Connection"] = "close"
  headers["Cache-Control"] = "no-store, max-age=0"
  if body then headers["Content-Length"] = tostring(#body) end
  local head = { ("HTTP/1.1 %d %s\r\n"):format(status, reason) }
  for k,v in pairs(headers) do head[#head+1] = ("%s: %s\r\n"):format(k,v) end
  head[#head+1] = "\r\n"
  local payload = table.concat(head) .. (body or "")
  client:write(payload, function() client:shutdown(); client:close() end)
end

local function url_decode(s)
  s = s:gsub("+", " ")
  s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
  return s
end

local function parse_request_line(line)
  local m, path = line:match("^(%u+)%s+([^%s]+)")
  return m, path
end

local function normalize_path(p)
  p = p:gsub("?.*$", "")      -- strip query
  p = p:gsub("#.*$", "")
  if p == "/" then return "/index.html" end
  return p
end

local function serve_path(client, root, p)
  local path = root .. p
  -- prevent ../ traversal
  if path:find("%.%.") then
    write_response(client, 400, nil, "Bad path\n")
    return
  end
  local data = read_file(path)
  if not data then
    if p == "/favicon.ico" then
      write_response(client, 204, { ["Content-Type"]="image/x-icon" }, nil)
      return
    end
    write_response(client, 404, nil, "Not found\n")
    return
  end
  write_response(client, 200, { ["Content-Type"]=mime_for(path) }, data)
end

local function on_client(sock)
  local client = uv.new_tcp()
  sock:accept(client)
  local buffer = ""
  client:read_start(function(err, chunk)
    if err then
      client:close()
      return
    end
    if chunk then
      buffer = buffer .. chunk
      -- very simple header end detection
      if buffer:find("\r\n\r\n", 1, true) or buffer:find("\n\n", 1, true) then
        local first = buffer:match("^[^\r\n]+")
        local method, raw_path = parse_request_line(first or "")
        if method ~= "GET" then
          write_response(client, 405, nil, "Only GET supported\n")
          return
        end
        local p = normalize_path(url_decode(raw_path or "/"))
        serve_path(client, M._root, p)
      end
    else
      -- eof with no full headers; close
      client:close()
    end
  end)
end

function M.ensure_started(port, root)
  if M._server and not M._server:is_closing() then
    return true
  end
  local srv = uv.new_tcp()
  local ok, err = srv:bind("127.0.0.1", port)
  if not ok then
    return false, ("cannot bind 127.0.0.1:%d (%s)"):format(port, err or "bind error")
  end
  local ok2, err2 = srv:listen(128, function() on_client(srv) end)
  if not ok2 then
    return false, ("listen failed on %d (%s)"):format(port, err2 or "listen error")
  end
  M._server = srv
  M._root   = root
  M._port   = port
  return true
end

return M

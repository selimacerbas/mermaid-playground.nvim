local uv = vim.loop
local M = {}

local state = {
	server = nil,
	port = 4070,
	html_path = nil,
	theme = "dark",
	latest_code = "",
	html_cache = nil,
}

local function read_file(path)
	local fd = assert(io.open(path, "rb"))
	local data = fd:read("*a")
	fd:close()
	return data
end

local function build_index_html()
	local html = state.html_cache or read_file(state.html_path)
	-- inject localStorage payload *before* the page's module script runs
	local payload_tbl = {
		src = state.latest_code or "",
		theme = state.theme or "dark",
	}
	local ok, payload_json = pcall(vim.json.encode, payload_tbl)
	if not ok then
		payload_json = "{}"
	end

	local inject = ([[<script>(function(){try{var prev=JSON.parse(localStorage.getItem('mermaidPlayground')||'{}');
  var next=Object.assign({},prev,%s);localStorage.setItem('mermaidPlayground',JSON.stringify(next));}catch(e){}})();</script>]]):format(
		payload_json
	)

	-- Put into <head> for early execution
	html = html:gsub("</head>", inject .. "</head>", 1)
	return html
end

local function http_ok(body, content_type)
	content_type = content_type or "text/html; charset=utf-8"
	local headers = table.concat({
		"HTTP/1.1 200 OK",
		"Content-Type: " .. content_type,
		"Content-Length: " .. tostring(#body),
		"Cache-Control: no-cache, no-store, must-revalidate",
		"Connection: close",
		"\r\n",
	}, "\r\n")
	return headers .. body
end

local function http_not_found()
	local body = "<h1>404</h1>"
	local headers = table.concat({
		"HTTP/1.1 404 Not Found",
		"Content-Type: text/html; charset=utf-8",
		"Content-Length: " .. tostring(#body),
		"Connection: close",
		"\r\n",
	}, "\r\n")
	return headers .. body
end

local function parse_request_line(data)
	local method, path = data:match("^(%u+)%s+([^%s]+)%s+HTTP")
	return method or "GET", path or "/"
end

local function handle_client(client)
	client:read_start(function(err, chunk)
		if err then
			return
		end
		if not chunk then
			client:shutdown()
			client:close()
			return
		end

		local req = chunk
		if not req:find("\r\n\r\n", 1, true) then
			-- wait for full headers (very simple; good enough for small GETs)
			return
		end

		local _, path = parse_request_line(req)
		local res
		if path == "/" then
			local body = build_index_html()
			res = http_ok(body, "text/html; charset=utf-8")
		elseif path == "/health" then
			res = http_ok("ok", "text/plain; charset=utf-8")
		else
			res = http_not_found()
		end

		client:write(res)
	end)
end

--- Start the tiny HTTP server if not running
---@param opts {port: integer, html_path: string, theme?: string}
---@return boolean ok, string|nil err
function M.start(opts)
	if state.server and not state.server:is_closing() then
		-- already running; just refresh config
		state.port = opts.port or state.port
		state.html_path = opts.html_path or state.html_path
		state.theme = opts.theme or state.theme
		if not state.html_cache then
			state.html_cache = read_file(state.html_path)
		end
		return true
	end

	state.port = opts.port or 4070
	state.html_path = assert(opts.html_path, "html_path is required")
	state.theme = opts.theme or state.theme
	state.html_cache = read_file(state.html_path)

	local server = uv.new_tcp()
	local ok_bind, err = server:bind("127.0.0.1", state.port)
	if not ok_bind then
		return false, err or ("cannot bind to port " .. tostring(state.port))
	end
	server:listen(64, function(err2)
		if err2 then
			return
		end
		local client = uv.new_tcp()
		server:accept(client)
		handle_client(client)
	end)

	state.server = server
	return true
end

function M.stop()
	if state.server and not state.server:is_closing() then
		pcall(state.server.close, state.server)
	end
	state.server = nil
end

function M.set_current_code(code)
	state.latest_code = code or ""
end

return M

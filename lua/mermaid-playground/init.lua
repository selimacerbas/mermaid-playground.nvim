local M = {}

local defaults = {
    run_priority = "nvim", -- 'nvim' | 'web' | 'both'
    select_block = "cursor", -- 'cursor' (current fence)
    autoupdate_events = { "InsertLeave", "TextChanged", "TextChangedI" },
    live_server = { port = 5555 },
    mermaid = {
        theme = "dark",  -- 'dark' | 'light'
        fit = "width",   -- 'none' | 'width' | 'height'
        packs = { "logos" }, -- icon packs to preload in viewer (Iconify)
    },
}

local state = {
    cfg = nil,
    started = false,
    proj_root = nil,
    cache_root = nil,
    link_path = nil, -- project_root/.mermaid-playground (symlink to cache)
}

local function project_root()
    -- Try to anchor in a project; otherwise use cwd
    local root = vim.fs.root(0, { ".git", "package.json", ".hg", ".root" }) or vim.loop.cwd()
    return root
end

local function sha1(s)
    -- lightweight hash for cache folder names
    return vim.fn.sha256(s):sub(1, 12)
end

local function ensure_dirs()
    state.proj_root = project_root()
    local key = sha1(state.proj_root)
    local base = vim.fn.stdpath("state") .. "/mermaid-playground/" .. key
    state.cache_root = base
    vim.fn.mkdir(base, "p")
    -- write viewer if missing
    if vim.fn.filereadable(base .. "/index.html") == 0 then
        local viewer = require("mermaid-playground.viewer_html")
        local f = assert(io.open(base .. "/index.html", "w"))
        f:write(viewer)
        f:close()
    end
    -- touch diagram file
    if vim.fn.filereadable(base .. "/diagram.mmd") == 0 then
        local f = assert(io.open(base .. "/diagram.mmd", "w"))
        f:write("")
        f:close()
    end

    -- Make a hidden symlink in project root so live-server can serve it
    state.link_path = state.proj_root .. "/.mermaid-playground"
    if vim.loop.fs_lstat(state.link_path) == nil then
        pcall(vim.loop.fs_symlink, state.cache_root, state.link_path)
    end

    -- Hide from git without touching user .gitignore (use repo-local excludes)
    if vim.loop.fs_lstat(state.proj_root .. "/.git") then
        local excl = state.proj_root .. "/.git/info/exclude"
        local exists = vim.fn.filereadable(excl) == 1 and vim.fn.readfile(excl) or {}
        local found = false
        for _, l in ipairs(exists) do
            if l == ".mermaid-playground" then
                found = true; break
            end
        end
        if not found then
            vim.fn.writefile(vim.list_extend(exists, { ".mermaid-playground" }), excl)
        end
    end
end

local function write_file(path, content)
    local f = assert(io.open(path, "w"))
    f:write(content or "")
    f:close()
end

local function system_open(url)
    local sys = vim.loop.os_uname().sysname
    if sys == "Darwin" then
        vim.fn.jobstart({ "open", url }, { detach = true })
    elseif sys:match("Windows") then
        vim.fn.jobstart({ "cmd", "/c", "start", "", url }, { detach = true })
    else
        vim.fn.jobstart({ "xdg-open", url }, { detach = true })
    end
end

local function prefers_dark()
    local bg = vim.o.background
    return (bg == "dark")
end

-- Build viewer URL
function M.preview_url()
    local port = M._cfg.live_server.port
    local q = {
        "theme=" .. (M._cfg.mermaid.theme or (prefers_dark() and "dark" or "light")),
        "fit=" .. (M._cfg.mermaid.fit or "width"),
        "packs=" .. table.concat(M._cfg.mermaid.packs or {}, ","),
    }
    return ("http://localhost:%d/.mermaid-playground/index.html?%s"):format(port, table.concat(q, "&"))
end

-- Live-server helpers
function M.start()
    ensure_dirs()
    -- start live-server if not running
    vim.cmd("silent! LiveServerStart")
    state.started = true
    -- open the viewer
    M.open()
end

function M.stop()
    vim.cmd("silent! LiveServerStop")
    state.started = false
end

function M.toggle()
    if state.started then M.stop() else M.start() end
end

function M.open()
    ensure_dirs()
    system_open(M.preview_url())
end

-- ===== Rendering =====

local ts = require("mermaid-playground.ts")

-- Extract mermaid fenced block under cursor
local function get_mermaid_under_cursor()
    local loc = ts.find_fence_under_cursor(0)
    if not loc then return nil, "No fenced code block under cursor." end
    local s, e, lang = loc[1], loc[2], loc[3]
    if lang ~= "mermaid" then
        return nil, ("Fenced block under cursor is '%s', not 'mermaid'."):format(lang ~= "" and lang or "unknown")
    end
    local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
    -- Strip any leading indentation uniformly (helpful for indented MD)
    local min_indent
    for _, l in ipairs(lines) do
        local sp = l:match("^(%s*)")
        if sp then
            min_indent = min_indent and math.min(min_indent, #sp) or #sp
        end
    end
    if min_indent and min_indent > 0 then
        for i, l in ipairs(lines) do lines[i] = l:sub(min_indent + 1) end
    end
    return table.concat(lines, "\n"), nil
end

-- Push code to the viewer’s diagram file
function M.render()
    ensure_dirs()
    local text, err = get_mermaid_under_cursor()
    if not text then
        vim.notify(err, vim.log.levels.WARN, { title = "mermaid-playground" })
        return
    end
    write_file(state.cache_root .. "/diagram.mmd", text)
    vim.notify("Rendered current mermaid block.", vim.log.levels.INFO, { title = "mermaid-playground" })
end

-- ===== Setup & Commands =====

M._cfg = defaults

function M.setup(opts)
    M._cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

    -- user commands
    vim.api.nvim_create_user_command("MermaidPlaygroundOpen", function() M.open() end, {})
    vim.api.nvim_create_user_command("MermaidPlaygroundToggle", function() M.toggle() end, {})
    vim.api.nvim_create_user_command("MermaidPlaygroundRender", function() M.render() end, {})

    -- auto-updates
    if M._cfg.autoupdate_events and #M._cfg.autoupdate_events > 0 then
        vim.api.nvim_create_augroup("MermaidPlaygroundAuto", { clear = true })
        vim.api.nvim_create_autocmd(M._cfg.autoupdate_events, {
            group = "MermaidPlaygroundAuto",
            pattern = { "*.md", "*.markdown", "*.mdx", "*.mmd" },
            callback = function()
                if state.started and (M._cfg.run_priority == "nvim" or M._cfg.run_priority == "both") then
                    local ok = pcall(M.render)
                    if not ok then
                        -- silent fail is fine here
                    end
                end
            end,
            desc = "Auto-render Mermaid fenced block under cursor",
        })
    end
end

-- exported helpers (used by your keymaps)
function M.preview_url_params()
    return {
        theme = M._cfg.mermaid.theme,
        fit = M._cfg.mermaid.fit,
        packs = M._cfg.mermaid.packs,
    }
end

return M

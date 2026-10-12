-- CLI tool to use for AI sessions (change to "gemini", "copilot", etc.)
local CLI_TOOL = "claude"

vim.g.sidekick_cli_tool = CLI_TOOL -- expose for autocmds.lua
local CLI_PREFIX = CLI_TOOL .. "_"
local CLI_PATTERN = "^" .. CLI_TOOL .. "_%d+$"
local CLI_NUM_PATTERN = "^" .. CLI_TOOL .. "_(%d+)$"
local CLI_DISPLAY = CLI_TOOL:sub(1, 1):upper() .. CLI_TOOL:sub(2)
local CLI_SK_FILE = "sk/cli/" .. CLI_TOOL .. ".lua"

-- Extra Ollama hosts whose models are appended to the <leader>ao picker.
-- Launching one of these sets OLLAMA_HOST for the sidekick session.
local OLLAMA_REMOTE_HOSTS = { "http://100.104.199.46:11434" }

-- Module-level state for dynamic session management
local _tool_base = nil
local _active_session = nil -- name of the currently visible session

-- Forward declaration so toggle_session (defined earlier) can call into the
-- winbar applier (defined later).
local apply_sidekick_winbar

local function get_tool_base()
    if _tool_base then
        return _tool_base
    end
    local f = vim.api.nvim_get_runtime_file(CLI_SK_FILE, false)[1]
    if f then
        local ok, ret = pcall(dofile, f)
        if ok and type(ret) == "table" then
            _tool_base = ret
        end
    end
    _tool_base = _tool_base or {}
    return _tool_base
end

local function make_tool()
    local base = get_tool_base()
    return {
        cmd = { CLI_TOOL },
        format = base.format,
        -- Setting `is_proc = false` is load-bearing: sidekick's Tool.get
        -- deep-merges the bundled `sk/cli/claude.lua` (which sets
        -- is_proc = "\\<claude\\>") with our override, and tbl_deep_extend
        -- has no way to express "delete this key" — so `nil` won't drop it.
        -- A boolean false survives the merge and trips the
        -- `type(is_proc) == "function"` check in Tool:is_proc, which then
        -- returns false. Without this, sessions.lua walks every tmux pane
        -- looking for any process matching `\<claude\>` and registers a
        -- State entry per pane → 5 cross-cwd rows in the picker, plus
        -- sidekick.cli.toggle pops its own disambiguator.
        is_proc = false,
    }
end

local function ensure_slot(n)
    local name = CLI_PREFIX .. n
    local tools = require("sidekick.config").cli.tools
    if not tools[name] then
        tools[name] = make_tool()
    end
    return name
end

local function next_available_slot()
    local tools = require("sidekick.config").cli.tools
    local i = 1
    while tools[CLI_PREFIX .. i] do
        i = i + 1
    end
    return i
end

-- Match slotted sessions only. The bare CLI_TOOL is intentionally excluded
-- so it never appears in the picker / kill list / tabs — sidekick's State.get
-- generates a placeholder entry for every tool in Config.cli.tools, and our
-- `Config.cli.tools[CLI_TOOL] = make_tool()` registration (needed only to
-- override the default `is_proc` scan) would otherwise surface as a pickable
-- "claude" entry that spawns a real tmux session on accidental selection.
local function is_cli_name(name)
    return name:match(CLI_PATTERN) ~= nil
        or name:match("^ollama%-") ~= nil
end

-- Re-register sidekick CLI tools for tmux sessions that survived a nvim
-- restart. Sidekick names tmux sessions "<tool_name> <hash>" where hash is
-- the first (16 - #tool_name) chars of sha256(cwd). The in-memory tool
-- registry resets on restart, so these orphans don't appear in the picker
-- until we re-register them. Reattachment itself works automatically because
-- sidekick's tmux backend uses `tmux new -A -s <id>`, which attaches to an
-- existing session of that name.
local function reconnect_sessions()
    if not vim.env.TMUX then return end
    local ok_session, Session = pcall(require, "sidekick.cli.session")
    local ok_config, Config = pcall(require, "sidekick.config")
    if not (ok_session and ok_config) then return end

    local lines = vim.fn.systemlist({ "tmux", "list-sessions", "-F", "#{session_name}" })
    if vim.v.shell_error ~= 0 then return end

    local full_hash = vim.fn.sha256(Session.cwd())
    Config.cli.tools = Config.cli.tools or {}
    for _, line in ipairs(lines) do
        local tool_name, hash = line:match("^(.-) (%w+)$")
        if tool_name and hash and is_cli_name(tool_name) and not Config.cli.tools[tool_name] then
            local expected_len = 16 - #tool_name
            if expected_len > 0 and #hash == expected_len and full_hash:sub(1, expected_len) == hash then
                if tool_name:match("^ollama%-") then
                    -- Original model isn't recoverable from the munged name,
                    -- but cmd is unused for `tmux new -A` when the session
                    -- already exists. cmd[1] just needs to be executable for
                    -- the picker's "installed" check.
                    Config.cli.tools[tool_name] = { cmd = { "ollama" } }
                else
                    Config.cli.tools[tool_name] = make_tool()
                end
            end
        end
    end
end

-- Resolve the live tmux session name for a sidekick session entry
local function mux_name_for(s)
    if s and s.session and s.session.mux_session then
        return s.session.mux_session
    end
    local ok, Session = pcall(require, "sidekick.cli.session")
    if ok and s and s.tool then
        return Session.sid({ tool = s.tool.name })
    end
    return nil
end

-- ========================================================================
-- Claude session title discovery
-- ------------------------------------------------------------------------
-- Map a tmux session -> the claude process running inside it -> the .jsonl
-- transcript that claude writes for that chat -> its customTitle (set by
-- the user via `/rename <name>` inside Claude Code).
-- ========================================================================

local function _trim(s)
    -- Wrap in extra parens so the gsub count return value is dropped — otherwise
    -- callers like `tonumber(_trim(x))` end up as `tonumber(str, count)` and fail.
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function _find_claude_pid_for_pane(pane_pid)
    if not pane_pid or pane_pid == "" then return nil end
    -- BFS down the process tree (depth 2 is plenty for tmux -> claude / wrappers)
    local function children(pid)
        return vim.fn.systemlist({ "pgrep", "-P", tostring(pid) })
    end
    local function comm(pid)
        return _trim(vim.fn.systemlist({ "ps", "-p", tostring(pid), "-o", "comm=" })[1] or "")
    end
    local frontier = { pane_pid }
    for _ = 1, 4 do
        local next_frontier = {}
        for _, pid in ipairs(frontier) do
            local c = comm(pid)
            -- claude binary often shows just as its version string ("2.1.126") on macOS
            if c:match("claude") or c:match("^[%d%.]+$") then
                return pid
            end
            for _, ch in ipairs(children(pid)) do
                table.insert(next_frontier, ch)
            end
        end
        if #next_frontier == 0 then return nil end
        frontier = next_frontier
    end
    return nil
end

-- /rename appends a new "custom-title" entry to the end of the jsonl, not
-- the start. Scan the whole file and keep the latest customTitle so renames
-- mid-session are reflected. The cheap `find` filter avoids JSON-parsing
-- every line — only candidate lines get decoded.
local function _read_custom_title(file)
    local f = io.open(file, "r")
    if not f then return nil end
    local title
    for line in f:lines() do
        if line:find('"customTitle"', 1, true) then
            local ok, obj = pcall(vim.json.decode, line)
            if ok and type(obj) == "table" and obj.customTitle then
                title = obj.customTitle
            end
        end
    end
    f:close()
    return title
end

-- Original cwd of a transcript, read from the first record that has one.
-- Used to disambiguate sibling worktrees that happen to encode to the same
-- ~/.claude/projects/<encoded> prefix (e.g. waste_frontend vs waste_frontend-2
-- both produce `-waste-frontend-2` because claude maps both `/` and `_` to `-`).
local function _read_session_cwd(file)
    local f = io.open(file, "r")
    if not f then return nil end
    local cwd
    for _ = 1, 30 do
        local line = f:read("*l")
        if not line then break end
        if line:find('"cwd"', 1, true) then
            local ok, obj = pcall(vim.json.decode, line)
            if ok and type(obj) == "table" and type(obj.cwd) == "string" then
                cwd = obj.cwd
                break
            end
        end
    end
    f:close()
    return cwd
end

-- First substantive user-message text in a transcript, used as a preview when
-- there's no customTitle. Skips leading non-user records (attachments,
-- permission-mode), skips empty / system-reminder-only / `Caveat:` messages,
-- strips XML-ish tags, collapses whitespace, truncates to 80 chars.
local function _read_first_user_message(file)
    local f = io.open(file, "r")
    if not f then return nil end
    local result
    for _ = 1, 200 do
        local line = f:read("*l")
        if not line then break end
        local ok, obj = pcall(vim.json.decode, line)
        if ok and type(obj) == "table" and obj.type == "user" and type(obj.message) == "table" then
            local content = obj.message.content
            local text
            if type(content) == "string" then
                text = content
            elseif type(content) == "table" then
                local parts = {}
                for _, p in ipairs(content) do
                    if type(p) == "table" and p.type == "text" and p.text then
                        parts[#parts + 1] = p.text
                    end
                end
                text = table.concat(parts, " ")
            end
            if text then
                text = text:gsub("[\n\r]", " ")
                text = text:gsub("<[^>]+>.-</[^>]+>", " ")
                text = text:gsub("<[^>]+>", " ")
                text = text:gsub("%s+", " ")
                text = text:gsub("^%s+", ""):gsub("%s+$", "")
                if text ~= "" and not text:match("^Caveat:") then
                    result = #text > 80 and (text:sub(1, 80) .. "…") or text
                    break
                end
            end
        end
    end
    f:close()
    return result
end

-- Elapsed time → epoch start. POSIX `ps -o etime=` returns `[[dd-]hh:]mm:ss`,
-- which works on both BSD ps (macOS) and GNU ps (Linux).
local function _pid_start_epoch(pid)
    local etime = _trim(vim.fn.systemlist({ "ps", "-p", tostring(pid), "-o", "etime=" })[1] or "")
    if etime == "" then return nil end
    local days, hours, mins, secs = 0, 0, 0, 0
    local d, h, m, s = etime:match("^(%d+)-(%d+):(%d+):(%d+)$")
    if d then
        days, hours, mins, secs = tonumber(d), tonumber(h), tonumber(m), tonumber(s)
    else
        h, m, s = etime:match("^(%d+):(%d+):(%d+)$")
        if h then
            hours, mins, secs = tonumber(h), tonumber(m), tonumber(s)
        else
            m, s = etime:match("^(%d+):(%d+)$")
            if not m then return nil end
            mins, secs = tonumber(m), tonumber(s)
        end
    end
    return os.time() - (days * 86400 + hours * 3600 + mins * 60 + secs)
end

-- Map a tmux pane to the .jsonl claude is writing to. Claude doesn't keep
-- the file open between appends, so we can't lsof it. Two-step strategy:
--   1. If `claude --resume <id>` is in the pid's argv, look up `<id>.jsonl`
--      directly — this is exact and covers all reattached sessions.
--   2. Otherwise (fresh claude), match the pid's start epoch against jsonl
--      file birthtimes. Each fresh session creates a new file at startup.
local function _jsonl_for_mux(mux_session)
    if not mux_session or mux_session == "" then return nil end
    local pane_pid = _trim(vim.fn.systemlist({ "tmux", "list-panes", "-t", mux_session, "-F", "#{pane_pid}" })[1] or "")
    if pane_pid == "" then return nil end
    local claude_pid = _find_claude_pid_for_pane(pane_pid)
    if not claude_pid then return nil end

    local args = _trim(vim.fn.systemlist({ "ps", "-p", tostring(claude_pid), "-o", "args=" })[1] or "")
    local id = args:match("%-%-resume%s+([%w%-]+)")
    if id then
        local matches = vim.fn.glob(vim.fn.expand("~/.claude/projects/*/" .. id .. ".jsonl"), false, true)
        return matches[1]
    end

    local start_epoch = _pid_start_epoch(claude_pid)
    if not start_epoch then return nil end
    local files = vim.fn.glob(vim.fn.expand("~/.claude/projects/*/*.jsonl"), false, true)
    local best_file, best_diff = nil, 30 -- 30s tolerance
    for _, file in ipairs(files) do
        local stat = vim.uv.fs_stat(file)
        local birth = stat and stat.birthtime and stat.birthtime.sec
        if birth then
            local diff = math.abs(birth - start_epoch)
            if diff < best_diff then
                best_diff = diff
                best_file = file
            end
        end
    end
    return best_file
end

-- Cache to avoid repeated shell-outs while a picker is open.
-- Key = mux_session, value = { info, expires_at }. `info` is
-- { id, title, preview, mtime } (matching the resume picker's per-row data)
-- or nil when no transcript could be resolved for the session.
local _title_cache = {}
local TITLE_TTL = 5

local function get_claude_session_info(mux_session)
    if not mux_session or mux_session == "" then return nil end
    local cached = _title_cache[mux_session]
    if cached and cached.expires_at > os.time() then
        return cached.info
    end
    local file = _jsonl_for_mux(mux_session)
    local info
    if file then
        local stat = vim.uv.fs_stat(file)
        info = {
            id = vim.fn.fnamemodify(file, ":t:r"),
            title = _read_custom_title(file),
            preview = _read_first_user_message(file),
            mtime = stat and stat.mtime and stat.mtime.sec or 0,
        }
    end
    _title_cache[mux_session] = { info = info, expires_at = os.time() + TITLE_TTL }
    return info
end

-- Human-friendly relative time, shared by the session pickers.
local function time_ago(t)
    local d = os.time() - t
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end

-- Returns { [claude_session_id] = sidekick_tool_name } for tmux sessions
-- currently running claude. Used by the resume picker to detect when the
-- chosen transcript is already attached, so we open the existing pane
-- instead of spawning a duplicate.
local function _active_claude_sessions()
    local map = {}
    if not vim.env.TMUX then return map end
    local lines = vim.fn.systemlist({ "tmux", "list-sessions", "-F", "#{session_name}" })
    if vim.v.shell_error ~= 0 then return map end
    for _, mux_name in ipairs(lines) do
        -- Sidekick sid format is "<tool_name> <hex_hash>" — split on the
        -- last space so this matches both claude_<n> and ollama-* slots.
        local tool_name = mux_name:match("^(.+) %x*$")
        if tool_name and is_cli_name(tool_name) then
            local file = _jsonl_for_mux(mux_name)
            if file then
                local id = vim.fn.fnamemodify(file, ":t:r")
                map[id] = tool_name
            end
        end
    end
    return map
end

-- ========================================================================

-- Enforce exclusive visibility: hide other terminals, show target
local function toggle_session(name)
    local ok, State = pcall(require, "sidekick.cli.state")
    if not ok then
        require("sidekick.cli").toggle({ name = name, focus = true })
        return
    end

    local states = State.get({ attached = true })

    -- Check if the target session is currently visible
    local target_visible = false
    for _, s in ipairs(states) do
        if s.tool.name == name and s.terminal and s.terminal:is_open() then
            target_visible = true
            break
        end
    end

    if target_visible then
        -- Target is shown — toggle will hide it
        _active_session = nil
        require("sidekick.cli").toggle({ name = name, focus = true })
    else
        -- Hide all other visible terminals first (synchronous)
        for _, s in ipairs(states) do
            if s.tool.name ~= name and is_cli_name(s.tool.name) and s.terminal and s.terminal:is_open() then
                s.terminal:hide()
            end
        end
        -- Show the target (async via State.with, runs after hides complete)
        _active_session = name
        require("sidekick.cli").toggle({ name = name, focus = true })
    end
    -- Defer so the window exists by the time we try to decorate it.
    vim.defer_fn(apply_sidekick_winbar, 50)
end

-- Toggle all sessions: hide all if any visible, show last active if none
local function toggle_all_sessions()
    local ok, State = pcall(require, "sidekick.cli.state")
    if not ok then
        require("sidekick.cli").toggle({ name = CLI_TOOL, focus = true })
        return
    end

    local states = State.get({ attached = true })
    local any_visible = false

    for _, s in ipairs(states) do
        if is_cli_name(s.tool.name) and s.terminal and s.terminal:is_open() then
            any_visible = true
            s.terminal:hide()
        end
    end

    if any_visible then
        _active_session = nil
    else
        local name = _active_session or ensure_slot(1)
        _active_session = name
        require("sidekick.cli").toggle({ name = name, focus = true })
    end
end

local function get_active_session_name()
    if _active_session then
        return _active_session
    end
    local ok, State = pcall(require, "sidekick.cli.state")
    if not ok then
        return nil
    end
    for _, s in ipairs(State.get({ attached = true })) do
        if is_cli_name(s.tool.name) and s.terminal and s.terminal:is_open() then
            _active_session = s.tool.name
            return s.tool.name
        end
    end
    return nil
end

-- Unified ordered slot list for the tab strip and Option-N switching:
-- claude_N slots numerically first, then ollama-* sessions alphabetically.
local function slot_list()
    local tools = require("sidekick.config").cli.tools or {}
    local nums, ollama = {}, {}
    for name, _ in pairs(tools) do
        local n = tonumber(name:match(CLI_NUM_PATTERN))
        if n then
            nums[#nums + 1] = n
        elseif name:match("^ollama%-") then
            ollama[#ollama + 1] = name
        end
    end
    table.sort(nums)
    table.sort(ollama)
    local list = {}
    for _, n in ipairs(nums) do list[#list + 1] = CLI_PREFIX .. n end
    for _, name in ipairs(ollama) do list[#list + 1] = name end
    return list
end

-- Winbar for the sidekick CLI window: a tab strip of all sessions in
-- slot_list() order, with the visible one highlighted. The displayed number
-- is the position in that list — the same number Option-N / <leader>aN
-- switches to. Ollama sessions show a shortened model label after the number.
function _G.__sidekick_agent_tabs()
    local list = slot_list()
    local parts = {}
    if #list == 0 then
        -- Always return non-empty so nvim allocates winbar height; otherwise
        -- the strip won't appear when slots show up later.
        parts[#parts + 1] = "%#TabLineFill# (no sessions) "
    else
        for i, name in ipairs(list) do
            local hl = (name == _active_session) and "%#TabLineSel#" or "%#TabLine#"
            local label = tostring(i)
            local model = name:match("^ollama%-(.+)$")
            if model then
                if #model > 16 then model = model:sub(1, 15) .. "…" end
                label = i .. ":" .. model
            end
            parts[#parts + 1] = hl .. "  " .. label .. "  %*"
        end
    end
    return table.concat(parts, "") .. "%#TabLineFill#%="
end

local WINBAR_EXPR = "%{%v:lua.__sidekick_agent_tabs()%}"

-- Apply the slot tab strip to every window currently showing a sidekick
-- terminal. Called directly from toggle_session and from the autocmd below
-- so we don't depend on a single event firing at the right time.
apply_sidekick_winbar = function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.bo[buf].filetype == "sidekick_terminal" then
                vim.wo[win].winbar = WINBAR_EXPR
            end
        end
    end
end

-- Registered at module top level (not inside the lazy `config`) so a
-- `:source` of this file or a `:Lazy reload sidekick.nvim` picks it up
-- without needing a full nvim restart. clear=true ensures duplicate-free
-- re-registration.
local _tabs_group = vim.api.nvim_create_augroup("SidekickAgentTabs", { clear = true })
vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType", "WinNew" }, {
    group = _tabs_group,
    callback = function() vim.schedule(apply_sidekick_winbar) end,
})
-- Catch already-open sidekick windows at the moment this file is sourced.
vim.schedule(apply_sidekick_winbar)

local keys = {
    {
        "<leader>aa",
        function()
            local ok, State = pcall(require, "sidekick.cli.state")
            if not ok then
                return
            end
            local states = State.get({})
            -- Sidekick discovers tmux sessions across all cwds for any tool it
            -- knows about (e.g. the bare "claude" default). Without filtering,
            -- the picker shows one row per cwd-session, so 4 unrelated projects
            -- all appear as "claude". Restrict to sessions whose tmux name's
            -- hash is a prefix of sha256(current cwd).
            local ok_session, Session = pcall(require, "sidekick.cli.session")
            local current_hash = ok_session and vim.fn.sha256(Session.cwd()) or nil
            local items = {}
            for _, s in ipairs(states) do
                if is_cli_name(s.tool.name) then
                    local include = true
                    if current_hash then
                        local mux = mux_name_for(s)
                        if mux then
                            local _, hash = mux:match("^(.-) (%w+)$")
                            if hash and current_hash:sub(1, #hash) ~= hash then
                                include = false
                            end
                        end
                    end
                    if include then
                        items[#items + 1] = s
                    end
                end
            end
            if #items == 0 then
                vim.notify("No " .. CLI_DISPLAY .. " sessions", vim.log.levels.INFO)
                return
            end
            -- Clear the cache so titles reflect current state
            _title_cache = {}
            -- Pad tool names to the longest one so titles line up regardless
            -- of slot-number digit width (claude_1 vs claude_10).
            local name_w = 0
            for _, s in ipairs(items) do
                local w = vim.fn.strdisplaywidth(s.tool.name)
                if w > name_w then name_w = w end
            end
            -- Same label width budget as the resume picker, so the "▸ <desc>"
            -- text gets truncated consistently rather than overflowing the
            -- vim.ui.select window.
            local LABEL_MAX = 50
            vim.ui.select(items, {
                prompt = CLI_DISPLAY .. " Sessions",
                format_item = function(s)
                    local status = (s.terminal and s.terminal:is_open()) and " [visible]"
                        or (s.session ~= nil) and " [attached]"
                        or ""
                    local pad = string.rep(" ", name_w - vim.fn.strdisplaywidth(s.tool.name))
                    local name = s.tool.name .. pad
                    local label = name
                    -- Prefer the user-set /rename title; fall back to the first
                    -- user message (same precedence as <leader>ar) so sessions
                    -- are distinguishable even without a custom title.
                    local info = get_claude_session_info(mux_name_for(s))
                    if info then
                        local desc = info.title or info.preview
                        if desc then
                            if vim.fn.strdisplaywidth(desc) > LABEL_MAX then
                                desc = vim.fn.strcharpart(desc, 0, LABEL_MAX - 1) .. "…"
                            end
                            label = name .. "  ▸ " .. desc
                        end
                        if info.mtime and info.mtime > 0 then
                            label = label .. "  (" .. time_ago(info.mtime) .. ")"
                        end
                    end
                    return label .. status
                end,
            }, function(choice)
                if choice then
                    -- Ensure the chosen tool is registered before toggling.
                    -- Slotted names (claude_N) go through ensure_slot; everything
                    -- else (bare "claude", "ollama-*") registers as itself so
                    -- sidekick.cli.toggle doesn't fall back to its own picker.
                    local Config = require("sidekick.config")
                    if not Config.cli.tools[choice.tool.name] then
                        local n = tonumber(choice.tool.name:match(CLI_NUM_PATTERN))
                        if n then
                            ensure_slot(n)
                        else
                            Config.cli.tools[choice.tool.name] = make_tool()
                        end
                    end
                    toggle_session(choice.tool.name)
                end
            end)
        end,
        desc = "Pick " .. CLI_DISPLAY .. " Session",
    },
    {
        "<leader>ar",
        function()
            -- Scope to the git tree so sessions started from subdirs of the
            -- project show up too (a common case when claude was launched
            -- from `dotfiles/` etc.). Falls back to plain cwd outside git.
            local cwd = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.getcwd(0), ":p"))
            local toplevel = _trim(vim.fn.systemlist({ "git", "-C", cwd, "rev-parse", "--show-toplevel" })[1] or "")
            local root = (vim.v.shell_error == 0 and toplevel ~= "") and vim.fs.normalize(toplevel) or cwd
            -- Claude encodes both `/` and `_` to `-` when naming project dirs
            -- under ~/.claude/projects (e.g. /Sites/waste_frontend becomes
            -- -Sites-waste-frontend), so mirror that here.
            local prefix = root:gsub("[/_]", "-")
            local base = vim.fn.expand("~/.claude/projects/")
            local files = vim.fn.glob(base .. prefix .. "/*.jsonl", false, true)
            vim.list_extend(files, vim.fn.glob(base .. prefix .. "-*/*.jsonl", false, true))

            -- The encoded-prefix glob is over-inclusive because the encoding
            -- is lossy (sibling dirs like waste_frontend / waste_frontend-2
            -- both match `-waste-frontend-2*`). Filter by reading each
            -- transcript's actual cwd and keeping only those equal to or
            -- under the git root.
            local root_slash = root .. "/"
            local kept = {}
            for _, file in ipairs(files) do
                local sess_cwd = _read_session_cwd(file)
                if sess_cwd == root or (sess_cwd and sess_cwd:sub(1, #root_slash) == root_slash) then
                    kept[#kept + 1] = file
                end
            end
            files = kept

            if #files == 0 then
                vim.notify("No " .. CLI_DISPLAY .. " transcripts for " .. root, vim.log.levels.INFO)
                return
            end

            local active = _active_claude_sessions()
            local sessions = {}
            for _, file in ipairs(files) do
                local stat = vim.uv.fs_stat(file)
                local mtime = stat and stat.mtime and stat.mtime.sec or 0
                local id = vim.fn.fnamemodify(file, ":t:r")
                sessions[#sessions + 1] = {
                    id = id,
                    file = file,
                    mtime = mtime,
                    title = _read_custom_title(file),
                    preview = _read_first_user_message(file),
                    active_in = active[id],
                }
            end
            table.sort(sessions, function(a, b) return a.mtime > b.mtime end)

            -- Pre-compute the leading "[id] label  (ago)" text per row so we
            -- can pad to a consistent width and right-align the active marker
            -- as its own column.
            local LABEL_MAX = 50
            local leads = {}
            local max_lead_w = 0
            for _, s in ipairs(sessions) do
                local label = s.title or s.preview or "(no preview)"
                if vim.fn.strdisplaywidth(label) > LABEL_MAX then
                    label = vim.fn.strcharpart(label, 0, LABEL_MAX - 1) .. "…"
                end
                local lead = string.format("[%s] %s  (%s)", s.id:sub(1, 8), label, time_ago(s.mtime))
                leads[s] = lead
                local w = vim.fn.strdisplaywidth(lead)
                if w > max_lead_w then max_lead_w = w end
            end

            vim.ui.select(sessions, {
                prompt = "Resume " .. CLI_DISPLAY .. " session",
                format_item = function(s)
                    local lead = leads[s]
                    if not s.active_in then return lead end
                    local pad = max_lead_w - vim.fn.strdisplaywidth(lead) + 3
                    return lead .. string.rep(" ", pad) .. "● " .. s.active_in
                end,
            }, function(choice)
                if not choice then return end
                local Config = require("sidekick.config")
                Config.cli.tools = Config.cli.tools or {}
                if choice.active_in then
                    -- Already running — open the existing slot.
                    if not Config.cli.tools[choice.active_in] then
                        if choice.active_in:match("^ollama%-") then
                            Config.cli.tools[choice.active_in] = { cmd = { "ollama" } }
                        else
                            Config.cli.tools[choice.active_in] = make_tool()
                        end
                    end
                    toggle_session(choice.active_in)
                else
                    -- Fresh slot launched with `claude --resume <id>`.
                    local n = next_available_slot()
                    local name = CLI_PREFIX .. n
                    Config.cli.tools[name] = {
                        cmd = { CLI_TOOL, "--resume", choice.id },
                        format = get_tool_base().format,
                    }
                    toggle_session(name)
                end
            end)
        end,
        desc = "Resume " .. CLI_DISPLAY .. " Session (history)",
    },
    {
        "<leader>an",
        function()
            local n = next_available_slot()
            local name = ensure_slot(n)
            toggle_session(name)
        end,
        desc = "New " .. CLI_DISPLAY .. " Session",
    },
    {
        "<leader>as",
        function()
            toggle_all_sessions()
        end,
        desc = "Toggle " .. CLI_DISPLAY .. " (Sidekick)",
        mode = { "n", "x" },
    },
    {
        "<leader>ad",
        function()
            require("sidekick.cli").close()
            _active_session = nil
        end,
        desc = "Detach CLI Session",
    },
    {
        "<leader>ak",
        function()
            local ok, State = pcall(require, "sidekick.cli.state")
            if not ok then
                return
            end
            local states = State.get({})
            local count = 0
            local tmux_sessions = {}
            local cfg_tools = require("sidekick.config").cli.tools
            local Session = require("sidekick.cli.session")
            for _, s in ipairs(states) do
                if is_cli_name(s.tool.name) then
                    if s.session and s.session.mux_session then
                        tmux_sessions[#tmux_sessions + 1] = s.session.mux_session
                    else
                        tmux_sessions[#tmux_sessions + 1] = Session.sid({ tool = s.tool.name })
                    end
                    if s.attached then
                        State.detach(s)
                    end
                    cfg_tools[s.tool.name] = nil
                    count = count + 1
                end
            end
            _active_session = nil
            for _, mux_name in ipairs(tmux_sessions) do
                vim.fn.system({ "tmux", "kill-session", "-t", mux_name })
            end
            if count > 0 then
                vim.notify("Killed " .. count .. " " .. CLI_DISPLAY .. " session(s)", vim.log.levels.INFO)
            else
                vim.notify("No " .. CLI_DISPLAY .. " sessions to kill", vim.log.levels.INFO)
            end
        end,
        desc = "Kill All " .. CLI_DISPLAY .. " Sessions",
    },
    {
        "<leader>ax",
        function()
            local name = _active_session
            if not name then
                vim.notify("No active " .. CLI_DISPLAY .. " session", vim.log.levels.INFO)
                return
            end
            local ok, State = pcall(require, "sidekick.cli.state")
            if not ok then
                return
            end
            local states = State.get({})
            local cfg_tools = require("sidekick.config").cli.tools
            local Session = require("sidekick.cli.session")
            for _, s in ipairs(states) do
                if s.tool.name == name then
                    local mux_name = (s.session and s.session.mux_session) or Session.sid({ tool = s.tool.name })
                    if s.attached then
                        State.detach(s)
                    end
                    cfg_tools[s.tool.name] = nil
                    _active_session = nil
                    vim.fn.system({ "tmux", "kill-session", "-t", mux_name })
                    vim.notify("Killed " .. CLI_DISPLAY .. " session: " .. name, vim.log.levels.INFO)
                    return
                end
            end
            vim.notify("Session not found: " .. name, vim.log.levels.WARN)
        end,
        desc = "Kill Active " .. CLI_DISPLAY .. " Session",
    },
    {
        "<leader>aD",
        function()
            if not vim.env.TMUX then
                vim.notify("Not running in tmux", vim.log.levels.WARN)
                return
            end
            local lines = vim.fn.systemlist({ "tmux", "list-sessions", "-F", "#{session_name}" })
            if vim.v.shell_error ~= 0 then return end

            -- Group sidekick tmux sessions by claude session id.
            local groups = {}
            for _, mux_name in ipairs(lines) do
                local tool_name = mux_name:match("^(.+) %x*$")
                if tool_name and is_cli_name(tool_name) then
                    local file = _jsonl_for_mux(mux_name)
                    if file then
                        local id = vim.fn.fnamemodify(file, ":t:r")
                        groups[id] = groups[id] or {}
                        table.insert(groups[id], { tool_name = tool_name, mux_name = mux_name })
                    end
                end
            end

            -- For each group with > 1 entry, keep the lowest claude_<n> slot
            -- (or alphabetic for ollama-*) and mark the rest for kill.
            local to_kill = {}
            for _, entries in pairs(groups) do
                if #entries > 1 then
                    table.sort(entries, function(a, b)
                        local na = tonumber(a.tool_name:match(CLI_NUM_PATTERN))
                        local nb = tonumber(b.tool_name:match(CLI_NUM_PATTERN))
                        if na and nb then return na < nb end
                        if na then return true end
                        if nb then return false end
                        return a.tool_name < b.tool_name
                    end)
                    for i = 2, #entries do
                        to_kill[#to_kill + 1] = entries[i]
                    end
                end
            end

            if #to_kill == 0 then
                vim.notify("No duplicate " .. CLI_DISPLAY .. " sessions", vim.log.levels.INFO)
                return
            end

            local names = {}
            for _, d in ipairs(to_kill) do names[#names + 1] = "  " .. d.mux_name end
            local choice = vim.fn.confirm(
                ("Kill %d duplicate %s session(s)?\n%s"):format(#to_kill, CLI_DISPLAY, table.concat(names, "\n")),
                "&Yes\n&No", 2
            )
            if choice ~= 1 then return end

            local ok, State = pcall(require, "sidekick.cli.state")
            local states = ok and State.get({}) or {}
            local cfg_tools = require("sidekick.config").cli.tools or {}
            for _, dup in ipairs(to_kill) do
                for _, s in ipairs(states) do
                    if s.tool.name == dup.tool_name and s.attached then
                        State.detach(s)
                    end
                end
                cfg_tools[dup.tool_name] = nil
                if _active_session == dup.tool_name then
                    _active_session = nil
                end
                vim.fn.system({ "tmux", "kill-session", "-t", dup.mux_name })
            end
            vim.notify(("Killed %d duplicate %s session(s)"):format(#to_kill, CLI_DISPLAY), vim.log.levels.INFO)
        end,
        desc = "Kill Duplicate " .. CLI_DISPLAY .. " Sessions",
    },
    {
        "<leader>aO",
        function()
            if not vim.env.TMUX then
                vim.notify("Not running in tmux", vim.log.levels.WARN)
                return
            end
            local lines = vim.fn.systemlist({ "tmux", "list-sessions", "-F", "#{session_name}" })
            if vim.v.shell_error ~= 0 then return end

            -- Orphan = sidekick-named tmux session whose pane no longer has a
            -- live claude process (claude crashed/exited but tmux lingers).
            local orphans = {}
            for _, mux_name in ipairs(lines) do
                local tool_name = mux_name:match("^(.+) %x*$")
                if tool_name and is_cli_name(tool_name) then
                    local pane_pid = _trim(vim.fn.systemlist({ "tmux", "list-panes", "-t", mux_name, "-F", "#{pane_pid}" })[1] or "")
                    if pane_pid ~= "" and not _find_claude_pid_for_pane(pane_pid) then
                        orphans[#orphans + 1] = { tool_name = tool_name, mux_name = mux_name }
                    end
                end
            end

            if #orphans == 0 then
                vim.notify("No orphan " .. CLI_DISPLAY .. " sessions", vim.log.levels.INFO)
                return
            end

            local names = {}
            for _, o in ipairs(orphans) do names[#names + 1] = "  " .. o.mux_name end
            local choice = vim.fn.confirm(
                ("Kill %d orphan %s session(s)?\n%s"):format(#orphans, CLI_DISPLAY, table.concat(names, "\n")),
                "&Yes\n&No", 2
            )
            if choice ~= 1 then return end

            local ok, State = pcall(require, "sidekick.cli.state")
            local states = ok and State.get({}) or {}
            local cfg_tools = require("sidekick.config").cli.tools or {}
            for _, orph in ipairs(orphans) do
                for _, s in ipairs(states) do
                    if s.tool.name == orph.tool_name and s.attached then
                        State.detach(s)
                    end
                end
                cfg_tools[orph.tool_name] = nil
                if _active_session == orph.tool_name then
                    _active_session = nil
                end
                vim.fn.system({ "tmux", "kill-session", "-t", orph.mux_name })
            end
            vim.notify(("Killed %d orphan %s session(s)"):format(#orphans, CLI_DISPLAY), vim.log.levels.INFO)
        end,
        desc = "Kill Orphan " .. CLI_DISPLAY .. " Sessions",
    },
    {
        "<leader>af",
        function()
            require("sidekick.cli").send({ msg = "{file}", name = get_active_session_name() })
        end,
        desc = "Send Current File to AI",
    },
    {
        "<leader>at",
        function()
            require("sidekick.cli").send({ msg = "{this}", name = get_active_session_name() })
        end,
        mode = { "x", "n" },
        desc = "Send This (context) to AI",
    },
    {
        "<leader>av",
        function()
            require("sidekick.cli").send({ msg = "{selection}", name = get_active_session_name() })
        end,
        mode = { "x" },
        desc = "Send Visual Selection to AI",
    },
    {
        "<leader>ay",
        function()
            vim.cmd('normal! "+y')
            require("sidekick.cli").send({ msg = "{selection}", name = get_active_session_name() })
        end,
        mode = { "x" },
        desc = "Copy to Clipboard + Send to AI",
    },
    {
        "<leader>ap",
        function()
            local clipboard = vim.fn.getreg("+")
            if clipboard and clipboard ~= "" then
                require("sidekick.cli").send({ msg = clipboard, name = get_active_session_name() })
            else
                vim.notify("Clipboard is empty", vim.log.levels.WARN)
            end
        end,
        mode = { "n" },
        desc = "Send Clipboard to AI",
    },
    {
        "<leader>ao",
        function()
            local items = {}
            local local_models = vim.fn.systemlist("ollama list 2>/dev/null | tail -n +2 | awk '{print $1}'")
            if vim.v.shell_error == 0 then
                for _, m in ipairs(local_models) do
                    table.insert(items, { model = m })
                end
            end
            for _, host in ipairs(OLLAMA_REMOTE_HOSTS) do
                local out = vim.fn.system({
                    "curl", "-sf", "--connect-timeout", "1", "--max-time", "3",
                    host .. "/api/tags",
                })
                local ok, data = false, nil
                if vim.v.shell_error == 0 then
                    ok, data = pcall(vim.json.decode, out)
                end
                if ok and type(data) == "table" and data.models then
                    for _, m in ipairs(data.models) do
                        table.insert(items, { model = m.name, host = host })
                    end
                else
                    vim.notify("Ollama host unreachable: " .. host, vim.log.levels.WARN)
                end
            end
            if #items == 0 then
                vim.notify("No Ollama models found. Try `ollama pull <model>`.", vim.log.levels.WARN)
                return
            end
            vim.ui.select(items, {
                prompt = "ollama launch claude --model:",
                format_item = function(item)
                    if not item.host then return item.model end
                    return item.model .. "  (" .. item.host:gsub("^https?://", ""):gsub(":%d+$", "") .. ")"
                end,
            }, function(choice)
                if not choice then return end
                local name = "ollama-" .. choice.model:gsub("[:/]", "-")
                if choice.host then
                    name = name .. "-" .. choice.host:gsub("^https?://", ""):gsub(":%d+$", ""):gsub("%W", "-")
                end
                local Config = require("sidekick.config")
                Config.cli.tools = Config.cli.tools or {}
                Config.cli.tools[name] = {
                    cmd = { "ollama", "launch", "claude", "--model", choice.model, "--yes" },
                    env = choice.host and { OLLAMA_HOST = choice.host } or nil,
                }
                toggle_session(name)
            end)
        end,
        desc = "Sidekick: ollama launch claude (model picker)",
    },
    {
        "<Tab>",
        function()
            if not require("sidekick").nes_jump_or_apply() then
                return "<Tab>"
            end
        end,
        expr = true,
        desc = "Goto/Apply Next Edit Suggestion",
    },
}

-- Switch to an existing slot only (position N in slot_list(), matching the
-- winbar tab strip — claude slots first, then ollama sessions). Creating
-- slots is reserved for <leader>an / <leader>ar / <leader>ao — these direct
-- keys should be cheap to mis-press without accidentally spawning empty
-- sessions.
local function switch_to_slot(i)
    local name = slot_list()[i]
    if not name then
        vim.notify(
            CLI_DISPLAY .. " Session " .. i .. " doesn't exist — use <leader>an / <leader>ar / <leader>ao to create",
            vim.log.levels.INFO
        )
        return
    end
    toggle_session(name)
end

-- Read by lua/worktrees.lua (<leader>aw) to show which slot's agent works in
-- which worktree and to jump to it.
_G.__sidekick_slots = {
    list = slot_list,
    mux = function(name)
        local ok, Session = pcall(require, "sidekick.cli.session")
        return ok and Session.sid({ tool = name }) or nil
    end,
    transcript = _jsonl_for_mux,
    info = get_claude_session_info,
    switch = switch_to_slot,
}

for i = 1, 9 do
    keys[#keys + 1] = {
        "<leader>a" .. i,
        function() switch_to_slot(i) end,
        desc = CLI_DISPLAY .. " Session " .. i,
    }
end

-- Option-N for direct session switching. Warp doesn't translate Option to
-- Alt/Meta — it sends the macOS Option-keyboard glyphs (Opt-1 = ¡, Opt-2 =
-- ™, etc.) — so we bind those literal characters instead of <M-N>. Bound in
-- normal/insert/terminal so it works while typing in the agent chat or
-- while editing code. Covers 1-9 (US layout glyphs); note Opt-8 (•) is now
-- bound, so it no longer types that glyph in these modes.
local option_glyphs = { "¡", "™", "£", "¢", "∞", "§", "¶", "•", "ª" }
for i, glyph in ipairs(option_glyphs) do
    keys[#keys + 1] = {
        glyph,
        function() switch_to_slot(i) end,
        mode = { "n", "i", "t" },
        desc = CLI_DISPLAY .. " Session " .. i .. " (Option-" .. i .. ")",
    }
end

return {
    {
        "github/copilot.vim",
        config = function()
            local function set_hl()
                local ok, palette = pcall(require, "tokyonight.colors")
                local c = ok and palette.setup({ style = "night" }) or {}
                vim.api.nvim_set_hl(0, "CopilotSuggestion", {
                    fg = c.comment or "#565f89",
                    italic = true,
                    force = true,
                })
            end
            set_hl()
            vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })
        end,
    },
    {
        "folke/sidekick.nvim",
        event = "VeryLazy",
        keys = keys,
        opts = {
            cli = {
                win = {
                    layout = "left",
                    keys = {
                        nav_left = false,
                        nav_down = false,
                        nav_up = false,
                        nav_right = false,
                    },
                    -- Sidekick re-applies its default wo table on every
                    -- fix_cursorline() call (cursor move, focus change),
                    -- which would otherwise reset winbar to "" every tick.
                    -- Routing our value through cli.win.wo makes sidekick's
                    -- own merge() keep it across those resets.
                    wo = {
                        winbar = "%{%v:lua.__sidekick_agent_tabs()%}",
                    },
                },
                mux = {
                    backend = "tmux",
                    enabled = true,
                },
            },
            ui = {
                border = "rounded",
            },
        },
        config = function(_, opts)
            require("sidekick").setup(opts)
            -- Override the bundled CLI_TOOL definition to drop `is_proc`. The
            -- default sidekick claude tool has `is_proc = "\\<claude\\>"`,
            -- which makes sidekick.cli.toggle scan every tmux pane for a
            -- "claude" process and pop its own picker when more than one is
            -- found (i.e. whenever you have claude running in multiple
            -- projects). With is_proc removed the tool resolves purely by
            -- Session.sid(cwd) — same model the slot tools (claude_N) use.
            local Config = require("sidekick.config")
            Config.cli.tools = Config.cli.tools or {}
            Config.cli.tools[CLI_TOOL] = make_tool()
            vim.schedule(reconnect_sessions)
            -- Winbar/autocmd registration lives at module top level; here we
            -- just ensure any sidekick windows that opened before this
            -- config ran get decorated too.
            vim.schedule(apply_sidekick_winbar)
        end,
    },
}

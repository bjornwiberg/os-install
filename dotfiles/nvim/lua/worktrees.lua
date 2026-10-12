-- Worktree overview (<leader>aw): one row per git worktree of the current repo
-- with change counts, touched openspec changes and which sidekick agent slot
-- is working in it. Nothing here changes nvim's cwd — sidekick keys its tmux
-- sessions on sha256(cwd), so a :cd would hide the running agents. Every
-- action is scoped to the worktree with `cwd = <path>` / `-C<path>` instead,
-- which keeps the sidekick panel and Option-N slots untouched.
local M = {}

local MAX_PREVIEW_LINES = 3000

local function git(cwd, args)
  local out = vim.fn.systemlist(vim.list_extend({ 'git', '-C', cwd }, args))
  return out, vim.v.shell_error == 0
end

local function default_branch(root)
  local out, ok = git(root, { 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD' })
  if ok and out[1] then
    return (out[1]:gsub('^origin/', ''))
  end
  for _, b in ipairs({ 'main', 'master' }) do
    local _, exists = git(root, { 'rev-parse', '--verify', '--quiet', 'refs/heads/' .. b })
    if exists then return b end
  end
  return nil
end

local function list_worktrees(root)
  local out = git(root, { 'worktree', 'list', '--porcelain' })
  local wts, cur = {}, nil
  for _, line in ipairs(out) do
    local path = line:match('^worktree (.+)$')
    if path then
      cur = { path = path }
      wts[#wts + 1] = cur
    elseif cur then
      cur.branch = cur.branch or line:match('^branch refs/heads/(.+)$')
      cur.head = cur.head or line:match('^HEAD (%x+)$')
      if line == 'detached' then cur.detached = true end
      if line == 'bare' then cur.bare = true end
      if line:match('^prunable') then cur.prunable = true end
    end
  end
  return vim.tbl_filter(function(w) return not w.bare end, wts)
end

-- Last cwd recorded in a claude transcript. Claude stamps every record with
-- the session cwd, which follows the agent into a worktree (EnterWorktree),
-- so the tail of the file says where the agent works right now.
local function transcript_cwd(file)
  local f = io.open(file, 'rb')
  if not f then return nil end
  local size = f:seek('end')
  f:seek('set', math.max(0, size - 262144))
  local data = f:read('*a')
  f:close()
  local cwd
  for m in data:gmatch('"cwd":"(.-)"') do cwd = m end
  return cwd
end

-- { [worktree path] = { { index, name, title }, ... } } for the sidekick
-- slots whose agent currently works inside that worktree.
local function agents_by_worktree(wts)
  local api = _G.__sidekick_slots
  local map = {}
  if not (api and vim.env.TMUX) then return map end
  for i, name in ipairs(api.list()) do
    local mux = api.mux(name)
    local file = mux and api.transcript(mux)
    local cwd = file and transcript_cwd(file)
    if cwd then
      -- Longest matching path wins: the main worktree is a prefix of the
      -- ones nested under .claude/worktrees/.
      local best
      for _, w in ipairs(wts) do
        if (cwd == w.path or cwd:sub(1, #w.path + 1) == w.path .. '/') and (not best or #w.path > #best.path) then
          best = w
        end
      end
      if best then
        local info = api.info and api.info(mux)
        map[best.path] = map[best.path] or {}
        table.insert(map[best.path], { index = i, name = name, title = info and (info.title or info.preview) })
      end
    end
  end
  return map
end

local function task_progress(file)
  local f = io.open(file, 'r')
  if not f then return nil end
  local done, total = 0, 0
  for line in f:lines() do
    local mark = line:match('^%s*[-*] %[([ xX])%]')
    if mark then
      total = total + 1
      if mark ~= ' ' then done = done + 1 end
    end
  end
  f:close()
  return total > 0 and { done = done, total = total } or nil
end

-- openspec changes this worktree has touched: committed since the base
-- branch plus anything uncommitted/untracked under openspec/changes/.
local function touched_specs(w)
  local seen, specs = {}, {}
  local paths = {}
  if w.base then
    vim.list_extend(paths, (git(w.path, { 'diff', '--name-only', '--merge-base', w.base, '--', 'openspec/changes' })))
  end
  for _, line in ipairs((git(w.path, { 'status', '--porcelain', '--untracked-files=all', '--', 'openspec/changes' }))) do
    paths[#paths + 1] = line:sub(4)
  end
  for _, p in ipairs(paths) do
    local name = p:match('openspec/changes/([^/]+)/')
    if name and name ~= 'archive' and not seen[name] then
      seen[name] = true
      specs[#specs + 1] = {
        name = name,
        dir = w.path .. '/openspec/changes/' .. name,
        tasks = task_progress(w.path .. '/openspec/changes/' .. name .. '/tasks.md'),
      }
    end
  end
  table.sort(specs, function(a, b) return a.name < b.name end)
  return specs
end

local function collect()
  local cwd = vim.fn.getcwd(0)
  local top, ok = git(cwd, { 'rev-parse', '--show-toplevel' })
  if not ok or not top[1] then
    vim.notify('Not inside a git repository', vim.log.levels.WARN)
    return nil
  end
  local wts = list_worktrees(top[1])
  local base = default_branch(top[1])
  for _, w in ipairs(wts) do
    w.label = w.branch or (w.head and w.head:sub(1, 8)) or '?'
    -- A worktree sitting on the base branch is compared against its own HEAD.
    w.base = (base and w.branch ~= base) and base or nil
    w.modified, w.untracked = 0, 0
    for _, line in ipairs((git(w.path, { 'status', '--porcelain' }))) do
      if line:sub(1, 2) == '??' then w.untracked = w.untracked + 1 else w.modified = w.modified + 1 end
    end
    if w.base then
      local counts = git(w.path, { 'rev-list', '--left-right', '--count', w.base .. '...HEAD' })[1] or ''
      local behind, ahead = counts:match('^(%d+)%s+(%d+)$')
      w.behind, w.ahead = tonumber(behind) or 0, tonumber(ahead) or 0
    end
    w.specs = touched_specs(w)
  end
  local agents = agents_by_worktree(wts)
  local items = {}
  for i, w in ipairs(wts) do
    w.agents = agents[w.path] or {}
    w.main = i == 1
    local spec_names = vim.tbl_map(function(s) return s.name end, w.specs)
    items[#items + 1] = vim.tbl_extend('force', w, {
      text = table.concat({ w.label, w.path, table.concat(spec_names, ' ') }, ' '),
      cwd = w.path,
    })
  end
  return items
end

local function format(item)
  local ret = {}
  local slots = vim.tbl_map(function(a) return '⌥' .. a.index end, item.agents)
  ret[#ret + 1] = { ('%-6s'):format(table.concat(slots, ' ')), #slots > 0 and 'DiagnosticOk' or 'Comment' }
  ret[#ret + 1] = { ('%-32s'):format(item.label), item.main and 'Title' or 'Special' }
  local counts = {}
  if (item.ahead or 0) > 0 then counts[#counts + 1] = '↑' .. item.ahead end
  if (item.behind or 0) > 0 then counts[#counts + 1] = '↓' .. item.behind end
  if item.modified > 0 then counts[#counts + 1] = '~' .. item.modified end
  if item.untracked > 0 then counts[#counts + 1] = '?' .. item.untracked end
  ret[#ret + 1] = { ('%-16s'):format(#counts > 0 and table.concat(counts, ' ') or 'clean'), #counts > 0 and 'DiagnosticWarn' or 'Comment' }
  for _, s in ipairs(item.specs) do
    local progress = s.tasks and (' ' .. s.tasks.done .. '/' .. s.tasks.total) or ''
    ret[#ret + 1] = { '◆ ' .. s.name .. progress .. '  ', 'DiagnosticInfo' }
  end
  if item.prunable then ret[#ret + 1] = { '(prunable)', 'DiagnosticError' } end
  return ret
end

local function diff_args(item)
  if item.base then return { '--merge-base', item.base } end
  return { 'HEAD' }
end

local function preview(ctx)
  local item = ctx.item
  local lines = { '# ' .. item.path }
  local vs = item.base and ('  vs ' .. item.base .. ': ↑' .. (item.ahead or 0) .. ' ↓' .. (item.behind or 0)) or ''
  lines[#lines + 1] = '# ' .. item.label .. vs
  for _, a in ipairs(item.agents) do
    lines[#lines + 1] = '# agent ⌥' .. a.index .. ' ' .. a.name .. (a.title and ('  ' .. a.title) or '')
  end
  for _, s in ipairs(item.specs) do
    local t = s.tasks and ('  tasks ' .. s.tasks.done .. '/' .. s.tasks.total) or ''
    lines[#lines + 1] = '# openspec ' .. s.name .. t
  end
  lines[#lines + 1] = ''
  vim.list_extend(lines, (git(item.path, { 'status', '--short', '--branch' })))
  lines[#lines + 1] = ''
  vim.list_extend(lines, (git(item.path, vim.list_extend({ 'diff', '--stat' }, diff_args(item)))))
  lines[#lines + 1] = ''
  vim.list_extend(lines, (git(item.path, vim.list_extend({ '--no-pager', 'diff', '--no-color' }, diff_args(item)))))
  if #lines > MAX_PREVIEW_LINES then
    lines = vim.list_slice(lines, 1, MAX_PREVIEW_LINES)
    lines[#lines + 1] = '# … truncated, open with <C-v> for the full diff'
  end
  ctx.preview:reset()
  ctx.preview:set_lines(lines)
  ctx.preview:set_title(item.label)
  ctx.preview:highlight({ ft = 'diff' })
end

local actions = {
  -- Hunks vs the base branch, opened in the editor window next to sidekick.
  wt_diff = function(picker, item)
    picker:close()
    Snacks.picker.git_diff({ cwd = item.path, base = item.base })
  end,
  -- Full review in a Diffview tab: merge-base..working tree incl. untracked.
  wt_diffview = function(picker, item)
    picker:close()
    local range = item.base and (item.base .. '...HEAD --imply-local') or ''
    vim.cmd('DiffviewOpen -C' .. vim.fn.fnameescape(item.path) .. ' ' .. range)
  end,
  wt_status = function(picker, item)
    picker:close()
    Snacks.picker.git_status({ cwd = item.path, show_empty = true })
  end,
  wt_files = function(picker, item)
    picker:close()
    Snacks.picker.files({ cwd = item.path, hidden = true, exclude = { 'node_modules', '.git', '.claude/worktrees' } })
  end,
  -- Touched openspec changes, or every active change when none is touched.
  wt_specs = function(picker, item)
    local dirs = vim.tbl_map(function(s) return s.dir end, item.specs)
    if #dirs == 0 then
      local root = item.path .. '/openspec/changes'
      if vim.fn.isdirectory(root) == 0 then
        vim.notify('No openspec/changes in ' .. item.label, vim.log.levels.INFO)
        return
      end
      dirs = { root }
    end
    picker:close()
    Snacks.picker.files({ cwd = item.path, dirs = dirs, exclude = { 'archive' } })
  end,
  wt_agent = function(picker, item)
    local a = item.agents[1]
    if not a then
      vim.notify('No sidekick agent works in ' .. item.label, vim.log.levels.INFO)
      return
    end
    picker:close()
    _G.__sidekick_slots.switch(a.index)
  end,
}

function M.pick()
  local items = collect()
  if not items then return end
  local function key(action)
    return { action, mode = { 'n', 'i' } }
  end
  Snacks.picker.pick({
    title = 'Worktrees',
    items = items,
    format = format,
    preview = preview,
    matcher = { sort_empty = false },
    sort = { fields = { 'idx' } },
    confirm = 'wt_diff',
    actions = actions,
    win = {
      input = {
        keys = {
          ['<c-v>'] = key('wt_diffview'),
          ['<c-g>'] = key('wt_status'),
          ['<c-o>'] = key('wt_files'),
          ['<c-s>'] = key('wt_specs'),
          ['<c-a>'] = key('wt_agent'),
        },
      },
    },
  })
end

return M

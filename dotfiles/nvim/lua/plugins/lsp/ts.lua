-- TypeScript LSP configuration
--
-- Two servers are declared, and exactly one attaches per project:
--
--   * `tsc`   -- the native (Go) TypeScript language server. TypeScript 7 ships
--               it inside the `typescript` package itself: `tsc --lsp --stdio`.
--               (lspconfig renamed this config from `tsgo`, now a deprecated alias.)
--               (The 6.x preview shipped it as `tsgo` from
--               `@typescript/native-preview`; both are handled below.)
--   * `ts_ls` -- the classic Node `typescript-language-server`, used for
--               projects still on TypeScript 5.x/6.x.
--
-- Why this matters: `typescript@7` no longer ships `lib/tsserver.js`, so
-- `typescript-language-server` silently falls back to its own bundled
-- TypeScript (Mason ships 5.4.4). That produces real false positives -- e.g. a
-- required `@ts-expect-error` gets reported as TS2578 "Unused '@ts-expect-error'
-- directive" because the old lib.d.ts has a non-generic `ArrayBufferView`.

local M = {}

--- Read the `typescript` version installed in `root`, if any.
--- @param root string
--- @return integer|nil major version
local function typescript_major(root)
  local pkg = vim.fs.joinpath(root, 'node_modules', 'typescript', 'package.json')
  local f = io.open(pkg, 'r')
  if not f then
    return nil
  end
  local contents = f:read('*a')
  f:close()
  local ok, decoded = pcall(vim.json.decode, contents)
  if not ok or type(decoded) ~= 'table' or type(decoded.version) ~= 'string' then
    return nil
  end
  return tonumber(decoded.version:match('^(%d+)%.'))
end

--- Resolve the native LSP command for a project root, or nil if unavailable.
--- Preference order:
---   1. `node_modules/.bin/tsgo`  (@typescript/native-preview, TS 6 preview)
---   2. `node_modules/.bin/tsc`   when the installed typescript is >= 7
---   3. a `tsgo` on $PATH         (globally installed native-preview)
--- @param root string|nil
--- @return string[]|nil
local function native_cmd(root)
  if root then
    local tsgo = vim.fs.joinpath(root, 'node_modules', '.bin', 'tsgo')
    if vim.fn.executable(tsgo) == 1 then
      return { tsgo, '--lsp', '--stdio' }
    end

    local major = typescript_major(root)
    if major and major >= 7 then
      local tsc = vim.fs.joinpath(root, 'node_modules', '.bin', 'tsc')
      if vim.fn.executable(tsc) == 1 then
        return { tsc, '--lsp', '--stdio' }
      end
    end
  end

  if vim.fn.executable('tsgo') == 1 then
    return { 'tsgo', '--lsp', '--stdio' }
  end

  return nil
end

--- Find the project root the same way nvim-lspconfig's `tsc` config does
--- (nearest package-manager lockfile, bailing out for Deno projects).
--- @param bufnr integer
--- @return string|nil
local function project_root(bufnr)
  local markers = { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'bun.lock', 'package.json' }
  local deno_root = vim.fs.root(bufnr, { 'deno.json', 'deno.jsonc' })
  local deno_lock_root = vim.fs.root(bufnr, { 'deno.lock' })
  local root = vim.fs.root(bufnr, markers)

  if deno_lock_root and (not root or #deno_lock_root > #root) then
    return nil
  end
  if deno_root and (not root or #deno_root >= #root) then
    return nil
  end
  return root
end

M.native_cmd = native_cmd
M.project_root = project_root

-- ---------------------------------------------------------------------------
-- Native server (TypeScript 7 `tsc --lsp`, or the `tsgo` preview binary)
-- ---------------------------------------------------------------------------
vim.lsp.config('tsc', {
  cmd = function(dispatchers, config)
    -- `config.root_dir` is not always populated when `cmd` is invoked (e.g.
    -- `:LspStart`), so fall back to resolving the root from the current buffer.
    local root = (config or {}).root_dir or project_root(0) or vim.fn.getcwd()
    local cmd = native_cmd(root) or { 'tsgo', '--lsp', '--stdio' }
    return vim.lsp.rpc.start(cmd, dispatchers)
  end,
  root_dir = function(bufnr, on_dir)
    local root = project_root(bufnr)
    if root and native_cmd(root) then
      on_dir(root)
    end
  end,
})

-- ---------------------------------------------------------------------------
-- Classic Node server -- only when no native server is available
-- ---------------------------------------------------------------------------
vim.lsp.config('ts_ls', {
  on_attach = function(client, bufnr)
    -- Basic LSP setup
  end,
  root_dir = function(bufnr, on_dir)
    local root = project_root(bufnr)
    if root and native_cmd(root) then
      -- The native server handles this project; don't start the Node one.
      return
    end
    on_dir(root or vim.fs.root(bufnr, { 'tsconfig.json', 'jsconfig.json', '.git' }))
  end,
})

vim.lsp.enable('tsc')
vim.lsp.enable('ts_ls')

return M

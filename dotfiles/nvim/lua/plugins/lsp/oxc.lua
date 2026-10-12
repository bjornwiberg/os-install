-- oxc LSP setup (oxlint + oxfmt)
--
-- Both server definitions come from nvim-lspconfig and only attach in
-- projects that use them: a .oxlintrc.json / .oxfmtrc.json (or
-- oxlint.config.ts / oxfmt.config.ts), or oxlint / oxfmt in package.json.
-- The project's node_modules/.bin binary wins over a global one, and oxlint
-- turns on type-aware linting by itself when tsgolint is installed.
--
-- On save (same pipeline as biome.lua):
--   1. fixAll — applies safe oxlint fixes
--   2. format — oxfmt (Prettier-compatible), last so it normalises the fixes
--
-- The prettier autocmd in plugins/editor.lua steps aside when oxfmt is
-- attached, so a project never gets formatted twice.

local augroup = vim.api.nvim_create_augroup("OxcOnSave", { clear = true })

local function apply_code_action(bufnr, client_name, action_kind)
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = client_name })[1]
  if not client then return end
  local result = client:request_sync('textDocument/codeAction', {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    range = {
      start = { line = 0, character = 0 },
      ['end'] = { line = vim.api.nvim_buf_line_count(bufnr), character = 0 },
    },
    context = { only = { action_kind }, diagnostics = {} },
  }, 3000, bufnr)

  if not (result and result.result) then return end
  for _, action in ipairs(result.result) do
    if action.edit then
      vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
    end
  end
end

-- One BufWritePre per buffer, registered by whichever oxc client attaches
-- first; each step checks for its own client so lint-only or format-only
-- projects work too.
local function register_on_save(bufnr)
  vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      apply_code_action(bufnr, 'oxlint', 'source.fixAll.oxc')
      if #vim.lsp.get_clients({ bufnr = bufnr, name = 'oxfmt' }) > 0 then
        vim.lsp.buf.format({ bufnr = bufnr, name = 'oxfmt', async = false })
      end
    end,
  })
end

-- Neovim < 0.11.3 calls cmd(dispatchers) without the resolved config, so
-- lspconfig's cmd can't see root_dir and falls back to a global binary that
-- usually isn't installed. Walk up from the buffer being attached (current
-- during the FileType autocmd) to the nearest node_modules/.bin/<bin>
-- instead — in a monorepo the package's own node_modules often lacks it and
-- the binary sits in the workspace root.
local function project_bin_cmd(bin)
  return function(dispatchers, config)
    local start = (config or {}).root_dir or vim.fs.dirname(vim.api.nvim_buf_get_name(0))
    local cmd = bin
    for dir in vim.fs.parents(vim.fs.joinpath(start, '_')) do
      local local_cmd = vim.fs.joinpath(dir, 'node_modules/.bin', bin)
      if vim.fn.executable(local_cmd) == 1 then
        cmd = local_cmd
        break
      end
    end
    return vim.lsp.rpc.start({ cmd, '--lsp' }, dispatchers)
  end
end

-- lspconfig's oxlint on_attach adds :LspOxlintFixAll — keep it.
local base_on_attach = vim.lsp.config.oxlint and vim.lsp.config.oxlint.on_attach

vim.lsp.config('oxlint', {
  cmd = project_bin_cmd('oxlint'),
  on_attach = function(client, bufnr)
    if base_on_attach then base_on_attach(client, bufnr) end
    register_on_save(bufnr)
  end,
})

vim.lsp.config('oxfmt', {
  cmd = project_bin_cmd('oxfmt'),
  on_attach = function(_client, bufnr)
    register_on_save(bufnr)
  end,
})

if not vim.g.oxc_lsp_enabled then
  vim.lsp.enable({ 'oxlint', 'oxfmt' })
  vim.g.oxc_lsp_enabled = true
end

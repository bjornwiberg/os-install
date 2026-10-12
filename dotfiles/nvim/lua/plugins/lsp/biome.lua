-- Biome LSP setup
--
-- On save:
--   1. organizeImports  — reorders/groups imports per biome.json assist config
--   2. fixAll           — applies safe lint fixes (e.g. JSX props sort, unused imports)
--   3. format           — whitespace, quotes, trailing commas
--
-- These must run sequentially: organizeImports rewrites the import block,
-- fixAll may touch those same lines, and formatting should be last so it
-- normalises whatever the previous actions emitted.
-- See: https://willcodefor.beer/posts/biome

-- Single shared augroup — bufnr pattern guarantees per-buffer isolation
-- without creating a new augroup per on_attach invocation. Using a stable
-- name + clear = true means re-sourcing this file (e.g. :so $MYVIMRC) wipes
-- the old autocmds before recreating them.
local augroup = vim.api.nvim_create_augroup("BiomeOnSave", { clear = true })

local code_action = require('plugins.lsp.code_action')

vim.lsp.config('biome', {
  -- Force UTF-8 position encoding. Biome only supports UTF-8, while ts_ls
  -- and Copilot default to UTF-16 — the mismatch triggers Neovim's
  -- "Multiple different client offset_encodings detected" warning.
  -- Declaring it explicitly here silences the warning for biome's side
  -- and keeps workspace edits in the client's utf-8 encoding.
  capabilities = {
    general = { positionEncodings = { "utf-8" } },
  },
  on_attach = function(_client, bufnr)
    -- Clear any previous BufWritePre autocmd for this buffer before
    -- adding a new one. Without this, re-attaches (e.g. two biome clients
    -- attaching to the same buffer, or :LspRestart) would register
    -- duplicate autocmds and run the save pipeline N times.
    vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })

    vim.api.nvim_create_autocmd("BufWritePre", {
      group = augroup,
      buffer = bufnr,
      callback = function()
        local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'biome' })
        if #clients == 0 then return end

        code_action.apply(bufnr, 'biome', 'source.organizeImports.biome')
        code_action.apply(bufnr, 'biome', 'source.fixAll.biome')

        vim.lsp.buf.format({ name = 'biome', async = false })
      end,
    })
  end,
})

-- Guard against double-enable (e.g. :so $MYVIMRC re-running this file while
-- biome is already enabled). vim.lsp.enable is idempotent for configs but
-- this keeps intent explicit.
if not vim.g.biome_lsp_enabled then
  vim.lsp.enable('biome')
  vim.g.biome_lsp_enabled = true
end

-- Shared on-save helper: request whole-buffer code actions of one kind from a
-- single LSP client and apply their edits synchronously.
--
-- Servers may return the action without its `edit` and only fill it in on
-- `codeAction/resolve` (Biome >= 2.5 does this for organizeImports/fixAll).
-- Applying only `action.edit` would silently do nothing, so resolve first.

local M = {}

---@param bufnr integer
---@param client_name string
---@param action_kind string
function M.apply(bufnr, client_name, action_kind)
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
    if not action.edit and action.data then
      local resolved = client:request_sync('codeAction/resolve', action, 3000, bufnr)
      if resolved and resolved.result then action = resolved.result end
    end
    if action.edit then
      vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
    end
  end
end

return M

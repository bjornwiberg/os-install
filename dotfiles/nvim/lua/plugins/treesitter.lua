-- nvim-treesitter `main` branch (the old `master` branch with
-- `nvim-treesitter.configs` is frozen and does not support Neovim 0.12).
-- Requires `tree-sitter` CLI and a C compiler (see README).
local parsers = {
  "bash",
  "css",
  "diff",
  "dockerfile",
  "git_rebase",
  "gitattributes",
  "gitcommit",
  "gitignore",
  "html",
  "javascript",
  "jsdoc",
  "json",
  "lua",
  "luadoc",
  "luap",
  "markdown",
  "markdown_inline",
  "printf",
  "python",
  "query",
  "regex",
  "toml",
  "tsx",
  "typescript",
  "vim",
  "vimdoc",
  "xml",
  "yaml",
}

return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      -- gcc's -O2 takes 7+ minutes on some grammars (e.g. gitcommit) vs ~4s at -O1.
      -- `tree-sitter build` honors CFLAGS; macOS (clang) is fast, so Linux only.
      if vim.fn.has('mac') == 0 and not vim.env.CFLAGS then
        vim.env.CFLAGS = '-O1'
      end

      if vim.fn.executable('tree-sitter') == 1 then
        require('nvim-treesitter').install(parsers)
      else
        vim.notify('tree-sitter CLI not found; parsers will not be installed', vim.log.levels.WARN)
      end

      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('treesitter_start', { clear = true }),
        callback = function(args)
          -- Only start if a parser is available for this filetype
          if not pcall(vim.treesitter.start, args.buf) then
            return
          end
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },
}

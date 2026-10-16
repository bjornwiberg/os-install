return {
  -- Editor plugin definitions
  {
    'prettier/vim-prettier',
    config = function()
      -- Editor Plugin Configurations
      -- Setup prettier configuration
      vim.g['prettier#autoformat'] = 0
      vim.g['prettier#autoformat_require_pragma'] = 0
      vim.g['prettier#exec_cmd_async'] = 1

      -- Format on save: Biome / oxfmt > Prettier > LSP > built-in indent (gg=G)
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*",
        callback = function()
          -- Skip special buffers
          if vim.bo.buftype ~= "" then return end

          -- Skip when Biome or oxfmt is attached — their own on-save pipelines
          -- (plugins/lsp/biome.lua, plugins/lsp/oxc.lua) format the buffer
          local clients = vim.lsp.get_clients({ bufnr = 0 })
          for _, client in ipairs(clients) do
            if client.name == 'biome' or client.name == 'oxfmt' then return end
          end

          -- Check if biome.json exists - skip to avoid conflicts
          local file_dir = vim.fn.expand('%:p:h')
          local biome_config = vim.fs.find({ 'biome.json', 'biome.jsonc' }, { upward = true, path = file_dir })[1]
          if biome_config then return end

          -- Same for oxfmt configs, in case the save beats the LSP attach
          local oxfmt_config = vim.fs.find({ '.oxfmtrc.json', '.oxfmtrc.jsonc', 'oxfmt.config.ts' }, { upward = true, path = file_dir })[1]
          if oxfmt_config then return end

          -- Try Prettier for supported file types when prettier binary is available
          local prettier_ft = {javascript=true, javascriptreact=true, typescript=true, typescriptreact=true, css=true, scss=true, html=true, json=true, markdown=true}
          if prettier_ft[vim.bo.filetype] then
            local has_prettier = vim.fn.executable('prettier') == 1
            if not has_prettier then
              has_prettier = vim.fs.find('node_modules/.bin/prettier', { upward = true, path = file_dir })[1] ~= nil
            end
            if has_prettier then
              pcall(vim.cmd, 'Prettier')
              return
            end
          end

          -- Try LSP formatting
          for _, client in ipairs(clients) do
            if client.supports_method("textDocument/formatting") then
              vim.lsp.buf.format({ async = false })
              return
            end
          end

          -- Fallback: built-in indent (skip for formats where it's destructive)
          local skip_indent = {yaml=true, yml=true, python=true, tmux=true, conf=true, sh=true, bash=true, zsh=true, dosini=true}
          if skip_indent[vim.bo.filetype] then return end
          local view = vim.fn.winsaveview()
          vim.cmd("silent normal! gg=G")
          vim.fn.winrestview(view)
        end,
      })
    end,
  },
  { 'editorconfig/editorconfig-vim' },

  -- ESLint
  { 'mfussenegger/nvim-lint' },

  -- Commenting (treesitter-native, handles JSX/TSX with {/* */} automatically)
  {
    'folke/ts-comments.nvim',
    event = 'VeryLazy',
    config = function()
      require('ts-comments').setup()
    end,
  },

  -- Dim inactive windows (disabled; set enabled = true to bring it back)
  {
    'levouh/tint.nvim',
    enabled = true,
    config = function()
      require('tint').setup({
        tint = -60,
        saturation = 0.5,
      })
    end,
  },

  -- Other useful plugins
  { "mg979/vim-visual-multi", branch = "master" },
  { 'christoomey/vim-tmux-navigator' },
  { 'tpope/vim-surround' },
  { 'dhruvasagar/vim-zoom' },

  -- Which-key for keybinding help
  {
    "folke/which-key.nvim",
    config = function()
      require("which-key").setup {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    end
  },

  {
    "rmagatti/auto-session",
    lazy = false,

    ---enables autocomplete for opts
    ---@module "auto-session"
    ---@type AutoSession.Config
    config = function()
      -- Only save buffers visible in windows, not all hidden/background buffers
      vim.o.sessionoptions = "curdir,folds,help,tabpages,winsize,terminal"

      local function close_junk_buffers()
        local visible = {}
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          visible[vim.api.nvim_win_get_buf(win)] = true
        end

        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(buf) then
            local name = vim.api.nvim_buf_get_name(buf)
            local buftype = vim.bo[buf].buftype

            -- Always close known junk patterns
            local is_junk = name:match("^term://")
            or name:match("node_modules/")
            or name:match("^magit://")
            or name:match("%[Claude Code%]")
            or name:match("Neotest Summary")

            -- Close non-visible regular file buffers (but leave terminals alone)
            local is_hidden_file = not visible[buf]
            and buftype == ""
            and name ~= ""

            if is_junk or is_hidden_file then
              pcall(vim.api.nvim_buf_delete, buf, { force = true })
            end
          end
        end
      end

      require("auto-session").setup({

        suppressed_dirs = { "~/", "~/Projects", "~/Downloads", "/" },
        bypass_save_filetypes = { "snacks_picker_list", "neotest-summary", "terminal", "nofile", "help" },
        pre_save_cmds = { close_junk_buffers },
        post_restore_cmds = { close_junk_buffers },
      })
    end,
  },
  {
    'MagicDuck/grug-far.nvim',
    opts = { headerMaxWidth = 80 },
    cmd = { "GrugFar", "GrugFarWithin" },
  },
}

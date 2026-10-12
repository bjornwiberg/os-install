return {
  -- LSP plugin definitions
  {
    'neovim/nvim-lspconfig',
    dependencies = { 'b0o/schemastore.nvim' },
    config = function()
      vim.opt.completeopt = { "menuone", "noselect", "popup" }
      vim.opt.updatetime = 350  -- 350ms (0.35 seconds)

      -- Per-server LSP configs
      require('plugins.lsp.ts')
      require('plugins.lsp.biome')
      require('plugins.lsp.oxc')
      require('plugins.lsp.pyright')
      require('plugins.lsp.jsonls')
      require('plugins.lsp.lua')
      require('plugins.lsp.clangd')
    end,
  },

  -- LSP Autocompletion plugin definitions
  {
    'hrsh7th/nvim-cmp',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-cmdline',
      'saadparwaiz1/cmp_luasnip',
      'L3MON4D3/LuaSnip',
      'onsails/lspkind.nvim',
    },
    config = function()
      -- LSP Autocompletion configuration
      local cmp = require'cmp'
      local luasnip = require'luasnip'
      local lspkind = require'lspkind'

      -- Pull colors from tokyonight and apply cmp highlights.
      -- Wrapped in a function + ColorScheme autocmd so they survive theme reloads.
      local c = require('tokyonight.colors').setup({ style = 'night' })

      -- Float background and border (global, applies to all floats)
      vim.api.nvim_set_hl(0, 'NormalFloat', { bg = c.bg_dark })
      vim.api.nvim_set_hl(0, 'FloatBorder', { fg = c.blue2, bg = c.bg_dark })

      -- Kind icon colors — deferred so they run after nvim-cmp's own
      -- startup which re-links CmpItemKind* to the base group
      local function set_kind_highlights()
        vim.api.nvim_set_hl(0, 'CmpItemKindFunction',    { fg = c.blue1 })
        vim.api.nvim_set_hl(0, 'CmpItemKindMethod',      { fg = c.blue1 })
        vim.api.nvim_set_hl(0, 'CmpItemKindConstructor', { fg = c.blue1 })
        vim.api.nvim_set_hl(0, 'CmpItemKindVariable',    { fg = c.teal })
        vim.api.nvim_set_hl(0, 'CmpItemKindField',       { fg = c.teal })
        vim.api.nvim_set_hl(0, 'CmpItemKindProperty',    { fg = c.teal })
        vim.api.nvim_set_hl(0, 'CmpItemKindClass',       { fg = c.yellow })
        vim.api.nvim_set_hl(0, 'CmpItemKindStruct',      { fg = c.yellow })
        vim.api.nvim_set_hl(0, 'CmpItemKindInterface',   { fg = c.green })
        vim.api.nvim_set_hl(0, 'CmpItemKindModule',      { fg = c.green })
        vim.api.nvim_set_hl(0, 'CmpItemKindEnum',        { fg = c.green })
        vim.api.nvim_set_hl(0, 'CmpItemKindEnumMember',  { fg = c.green })
        vim.api.nvim_set_hl(0, 'CmpItemKindKeyword',     { fg = c.red })
        vim.api.nvim_set_hl(0, 'CmpItemKindOperator',    { fg = c.red })
        vim.api.nvim_set_hl(0, 'CmpItemKindConstant',    { fg = c.orange })
        vim.api.nvim_set_hl(0, 'CmpItemKindSnippet',     { fg = c.purple })
        vim.api.nvim_set_hl(0, 'CmpItemKindText',        { fg = c.fg_dark })
        vim.api.nvim_set_hl(0, 'CmpItemKindFile',        { fg = c.fg_dark })
        vim.api.nvim_set_hl(0, 'CmpItemKindFolder',      { fg = c.fg_dark })
      end

      vim.defer_fn(set_kind_highlights, 100)
      vim.api.nvim_create_autocmd('ColorScheme', {
        callback = function() vim.defer_fn(set_kind_highlights, 100) end
      })

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = {
          ['<C-s>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.close(),
          ['<C-d>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              for _ = 1, 5 do cmp.select_next_item({ behavior = cmp.SelectBehavior.Select }) end
            else
              fallback()
            end
          end, { "i", "s" }),
          ['<C-u>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              for _ = 1, 5 do cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select }) end
            else
              fallback()
            end
          end, { "i", "s" }),
          ['<C-g>'] = cmp.mapping.scroll_docs(4),
          ['<C-f>'] = cmp.mapping.scroll_docs(-4),
          ['<CR>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              if luasnip.expandable() then
                luasnip.expand()
              else
                cmp.confirm({ select = true })
              end
            else
              fallback()
            end
          end),
          ["<C-j>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<C-k>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        },
        window = {
          completion = {
            border = 'rounded',
            winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual,Search:None',
          },
          documentation = {
            border = 'rounded',
            winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual,Search:None',
            max_width = 80,
            max_height = 30,
          },
        },
        formatting = {
          format = lspkind.cmp_format({
            mode = 'symbol_text',  -- show icon + text label
            maxwidth = 50,
            ellipsis_char = '...',
          }),
        },
        sources = {
          { name = 'nvim_lsp' },
          { name = 'buffer' },
          { name = 'path' },
        },
      })
    end,
  },
}

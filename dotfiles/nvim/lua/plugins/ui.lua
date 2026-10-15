return {
  -- Rendered markdown (inline preview)
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    opts = {},
  },

  -- Markdown browser preview (Mermaid support)
  {
    'iamcco/markdown-preview.nvim',
    ft = { 'markdown' },
    -- Shell build: the mkdp#util#install autoload isn't on the rtp yet on a fresh install.
    build = 'cd app && npx --yes yarn install',
    init = function()
      vim.g.mkdp_filetypes = { 'markdown' }
    end,
  },

  -- Color scheme
  {
    'folke/tokyonight.nvim',
    priority = 1000,
    config = function()
      -- Transparent background: the terminal's own background shows through.
      -- Floats keep their dark background so popups stay readable.
      require('tokyonight').setup({
        transparent = true,
        styles = { sidebars = 'transparent', floats = 'dark' },
        -- The snacks explorer and the sidekick panel link to NormalFloat; make
        -- those transparent too, so only real popups keep a background.
        -- fg is required: a group with only bg = NONE counts as cleared, and the
        -- plugins' default links would point it back at NormalFloat.
        on_highlights = function(hl, c)
          for _, group in ipairs({
            'SnacksNormal', 'SnacksNormalNC', 'SnacksPicker', 'SnacksPickerList',
            'SnacksPickerInput', 'SnacksPickerBox', 'SidekickChat',
          }) do
            hl[group] = { fg = c.fg, bg = 'NONE' }
          end
        end,
      })
      vim.cmd('colorscheme tokyonight-night')
    end,
  },

  -- Icons (mini.icons replaces nvim-web-devicons for fzf-lua glob support)
  {
    'echasnovski/mini.icons',
    version = false,
    config = function()
      require('mini.icons').setup()
      -- Make fzf-lua and other plugins that use nvim-web-devicons API use mini.icons
      require('mini.icons').mock_nvim_web_devicons()
    end,
  },

  -- File explorer
  { 'nvim-tree/nvim-tree.lua',
    config = function()
      require('nvim-tree').setup({
        sort_by = "case_sensitive",
        view = { width = 30 },
        renderer = { group_empty = true },
        filters = { dotfiles = false },
      })
    end,
  },
  { 'nvim-tree/nvim-web-devicons' },

  -- Scrollbar plugin
  {
    "petertriho/nvim-scrollbar",
    config = function()
      require("scrollbar").setup()
    end,
  },

  -- Tab bar plugin
  {
    'romgrk/barbar.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
  },

  -- Status line — sindrets-style: monochrome dim palette, NerdFont icons,
  -- single global statusline. Order mirrors his feline layout.
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      -- Pull palette directly from tokyonight so the statusline stays in sync
      -- with the colorscheme. Add a falsey fallback if tokyonight isn't loaded yet.
      local ok, tn = pcall(function()
        return require('tokyonight.colors').setup({ style = 'night' })
      end)
      tn = ok and tn or {}
      local colors = {
        bg       = tn.bg_dark   or '#16161e',
        fg       = tn.fg        or '#c0caf5',
        fg_dim   = tn.fg_dark   or '#a9b1d6',
        yellow   = tn.yellow    or '#e0af68',
        cyan     = tn.cyan      or '#7dcfff',
        green    = tn.green     or '#9ece6a',
        orange   = tn.orange    or '#ff9e64',
        violet   = tn.purple    or '#9d7cd8',
        magenta  = tn.magenta   or '#bb9af7',
        blue     = tn.blue      or '#7aa2f7',
        red      = tn.red       or '#f7768e',
      }
      -- Statusline bg is NONE so it blends with the editor background.
      local bg = 'NONE'
      local mode_text = function(c) return { fg = c, bg = bg, gui = 'bold' } end
      local flat = { fg = colors.fg_dim, bg = bg }
      local theme = {
        normal = {
          a = mode_text(colors.blue),
          b = flat, c = flat, x = flat, y = flat,
          z = { fg = colors.fg, bg = bg },
        },
        insert   = { a = mode_text(colors.green) },
        visual   = { a = mode_text(colors.magenta) },
        replace  = { a = mode_text(colors.red) },
        command  = { a = mode_text(colors.yellow) },
        terminal = { a = mode_text(colors.cyan) },
        inactive = {
          a = { fg = colors.fg_dim, bg = bg },
          b = { fg = colors.fg_dim, bg = bg },
          c = { fg = colors.fg_dim, bg = bg },
        },
      }

      require('lualine').setup({
        options = {
          theme = theme,
          component_separators = '',
          section_separators = '',
          globalstatus = true,
          disabled_filetypes = { statusline = { 'snacks_dashboard' } },
        },
        sections = {
          lualine_a = {
            { 'mode', padding = { left = 1, right = 1 } },
          },
          lualine_b = {
            {
              'filetype',
              icon_only = true,
              colored = true,
              padding = { left = 1, right = 0 },
            },
            {
              'filename',
              path = 1,
              padding = { left = 1, right = 1 },
              symbols = { modified = ' ●', readonly = ' ', unnamed = '[No Name]' },
              color = { fg = colors.fg },
            },
            {
              'diff',
              source = function()
                local gs = vim.b.gitsigns_status_dict
                if gs then
                  return { added = gs.added, modified = gs.changed, removed = gs.removed }
                end
              end,
              symbols = { added = ' ', modified = '󰝤 ', removed = ' ' },
              diff_color = {
                added    = { fg = colors.green },
                modified = { fg = colors.orange },
                removed  = { fg = colors.red },
              },
            },
          },
          lualine_c = {},
          lualine_x = {
            {
              'diagnostics',
              symbols = { error = '✗ ', warn = '▲ ', info = 'ℹ ', hint = ' ' },
              colored = true,
              diagnostics_color = {
                error = { fg = colors.red },
                warn  = { fg = colors.yellow },
                info  = { fg = colors.blue },
                hint  = { fg = colors.cyan },
              },
              padding = { left = 1, right = 1 },
            },
          },
          lualine_y = {
            { 'location', padding = { left = 1, right = 0 } },
            { 'progress', padding = { left = 1, right = 0 } },
            {
              function() return ' ' .. vim.api.nvim_buf_line_count(0) end,
              padding = { left = 1, right = 0 },
            },
            { 'filetype', icon_only = false, colored = true, padding = { left = 1, right = 0 } },
            {
              function()
                local et = vim.bo.expandtab and 'SPACES' or 'TABS'
                return string.format('☰ %s %d', et, vim.bo.shiftwidth)
              end,
              padding = { left = 1, right = 0 },
            },
            {
              'encoding',
              fmt = function(s) return '⌶ ' .. s:upper() end,
              padding = { left = 1, right = 0 },
            },
          },
          lualine_z = {
            {
              'branch',
              icon = { '', align = 'left' },
              padding = { left = 1, right = 1 },
            },
          },
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = { { 'filename', path = 1 } },
          lualine_x = { 'location' },
          lualine_y = {},
          lualine_z = {},
        },
      })
    end,
  },

  -- Per-window filename label in the top-right corner.
  -- Layout: [diagnostics] [git diff] [filetype icon] [filename] [window#]
  -- Source: https://github.com/b0o/incline.nvim#diagnostics--git-diff--icon--filename
  {
    'b0o/incline.nvim',
    event = 'VeryLazy',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      local devicons = require('nvim-web-devicons')
      require('incline').setup({
        window = {
          margin = { vertical = 0, horizontal = 1 },
          padding = { left = 1, right = 1 },
          placement = { vertical = 'top', horizontal = 'right' },
          options = { signcolumn = 'no', wrap = false },
          winhighlight = {
            active   = { Normal = 'NormalFloat' },
            inactive = { Normal = 'NormalFloat' },
          },
        },
        hide = { cursorline = false, focused_win = false, only_win = false },
        render = function(props)
          local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ':t')
          if filename == '' then filename = '[No Name]' end
          local ft_icon, ft_color = devicons.get_icon_color(filename)
          local modified = vim.bo[props.buf].modified

          return {
            { (ft_icon or '') .. ' ', guifg = ft_color, guibg = 'none' },
            {
              filename,
              guifg = ft_color or '#7dcfff',
              gui = modified and 'bold,italic' or 'bold',
            },
          }
        end,
      })
    end,
  },

  -- Indent guides (via snacks.nvim)

  -- Snacks.nvim (explorer + utilities)
  {
    "folke/snacks.nvim",
    config = function(_, opts)
      require("snacks").setup(opts)
      -- Re-apply preview window keymaps after each buffer swap.
      -- Snacks only calls win:map() on the initial scratch buffer, so file
      -- preview buffers lose our <C-h>/<C-l>/<CR> bindings without this.
      local preview = require("snacks.picker.core.preview")
      local orig_set_buf = preview.set_buf
      preview.set_buf = function(self, buf)
        orig_set_buf(self, buf)
        self.win:map()
      end
    end,
    opts = {
      statuscolumn = { enabled = true },
      zen = {
        show = {
          statusline = true,
          tabline = false,
        },
      },
      explorer = {
        replace_netrw = true,
      },
      indent = {
        indent = {
          hl = {
            "SnacksIndent1",
            "SnacksIndent2",
            "SnacksIndent3",
            "SnacksIndent4",
            "SnacksIndent5",
            "SnacksIndent6",
            "SnacksIndent7",
            "SnacksIndent8",
          },
        },
      },
      picker = {
        ui_select = true,
        matcher = {
          frecency = true,
        },
        previewers = {
          git = {
            args = { "-c", "diff.ignoreAllSpace=true" },
          },
        },
        actions = {
          jump_to_preview_line = function(picker)
            local item = picker:current()
            if not item then return end
            -- Don't run confirm for commit items — it would git_checkout/detach.
            if item.commit then return end
            local pos = vim.api.nvim_win_get_cursor(0)
            item.pos = { pos[1], pos[2] }
            picker:action("confirm")
          end,
        },
        win = {
          input = {
            keys = {
              ["<c-g>"] = { "preview_scroll_up", mode = { "i", "n" } },
              ["<c-l>"] = { "focus_preview", mode = { "i", "n" } },
            },
          },
          list = {
            keys = {
              ["<c-g>"] = "preview_scroll_up",
              ["<c-l>"] = "focus_preview",
            },
          },
          preview = {
            keys = {
              ["<c-h>"] = "focus_list",
              ["<CR>"] = "jump_to_preview_line",
            },
          },
        },
        -- Docked git-changes panel: list of changed files on top, live diff
        -- preview of the selected file below. Opt in per-call via
        -- `git_status({ layout = "git_panel" })` so the default `<leader>gs`
        -- float stays untouched.
        layouts = {
          -- Bottom pane listing changed files, no diff preview. Like the
          -- git_status picker but docked along the bottom edge, list only.
          git_panel = {
            preview = false,
            layout = {
              box = "vertical",
              backdrop = false,
              width = 0,
              height = 0.3,
              position = "bottom",
              border = "top",
              title = " Git changes ",
              title_pos = "left",
              { win = "input", height = 1, border = "bottom" },
              { win = "list", border = "none" },
            },
          },
        },
        sources = {
          explorer = {
            layout = {
              preset = "sidebar",
              preview = false,
              layout = {
                position = "right",
                width = 35,
              },
            },
            hidden = true,
            ignored = true,
            auto_close = false,
            follow_file = true,
            watch = true,
            win = {
              input = {
                keys = {
                  ["<Esc>"] = { function() end, desc = "noop (don't close explorer)" },
                  -- Skip nvim window navigation and go straight to the tmux
                  -- pane on the right — TmuxNavigateRight gets confused inside
                  -- floating-picker windows and falls back to the editor.
                  ["<c-l>"] = {
                    function()
                      if vim.env.TMUX then
                        vim.fn.system('tmux select-pane -R')
                      else
                        vim.cmd('TmuxNavigateRight')
                      end
                    end,
                    mode = { "i", "n" },
                    desc = "tmux pane right",
                  },
                },
              },
              list = {
                keys = {
                  ["<Esc>"] = { function() end, desc = "noop (don't close explorer)" },
                  ["<c-l>"] = {
                    function()
                      if vim.env.TMUX then
                        vim.fn.system('tmux select-pane -R')
                      else
                        vim.cmd('TmuxNavigateRight')
                      end
                    end,
                    desc = "tmux pane right",
                  },
                  ["<leader>ghf"] = {
                    function()
                      local pickers = Snacks.picker.get({ source = "explorer" })
                      local item = pickers[1] and pickers[1]:current()
                      if item and item.file and not item.dir then
                        local cwd = vim.fn.fnamemodify(item.file, ":h")
                        local rel = vim.fn.system("git -C " .. vim.fn.shellescape(cwd) .. " ls-files --full-name " .. vim.fn.shellescape(item.file)):gsub("%s+$", "")
                        local branch = vim.fn.system("git -C " .. vim.fn.shellescape(cwd) .. " rev-parse --abbrev-ref HEAD"):gsub("%s+$", "")
                        local remote = vim.fn.system("git -C " .. vim.fn.shellescape(cwd) .. " config --get remote.origin.url"):gsub("%s+$", ""):gsub("^git@github.com:", "https://github.com/"):gsub("%.git$", "")
                        local url = remote .. "/blob/" .. branch .. "/" .. rel
                        vim.fn.setreg('+', url)
                        vim.notify("Copied: " .. url)
                      end
                    end,
                    desc = "Copy GitHub file URL",
                  },
                  ["<leader>ghp"] = {
                    function()
                      local pickers = Snacks.picker.get({ source = "explorer" })
                      local item = pickers[1] and pickers[1]:current()
                      if item and item.file and not item.dir then
                        local cwd = vim.fn.fnamemodify(item.file, ":h")
                        local rel = vim.fn.system("git -C " .. vim.fn.shellescape(cwd) .. " ls-files --full-name " .. vim.fn.shellescape(item.file)):gsub("%s+$", "")
                        local commit = vim.fn.system("git -C " .. vim.fn.shellescape(cwd) .. " log -n 1 --pretty=format:%H -- " .. vim.fn.shellescape(item.file)):gsub("%s+$", "")
                        local remote = vim.fn.system("git -C " .. vim.fn.shellescape(cwd) .. " config --get remote.origin.url"):gsub("%s+$", ""):gsub("^git@github.com:", "https://github.com/"):gsub("%.git$", "")
                        local url = remote .. "/blob/" .. commit .. "/" .. rel
                        vim.fn.setreg('+', url)
                        vim.notify("Copied: " .. url)
                      end
                    end,
                    desc = "Copy GitHub permalink",
                  },
                },
              },
            },
          },
        },
      },
    },
  },

  -- FZF with icons using fzf-lua (better icon support)
  { 'junegunn/fzf', build = './install --bin' },  -- FZF binary
  {
    'ibhagwan/fzf-lua',  -- Lua wrapper with icon support
    config = function()
      require('fzf-lua').setup({
        winopts = {
          height = 0.85,
          width = 0.80,
          preview = {
            default = 'bat',
            border = 'border',
            wrap = 'nowrap',
            hidden = 'nohidden',
            vertical = 'down:45%',
            horizontal = 'right:60%',
          },
        },
        keymap = {
          builtin = {
            ["<C-u>"] = "half-page-up",
            ["<C-d>"] = "half-page-down",
            ["<S-down>"] = "preview-page-down",
            ["<S-up>"]   = "preview-page-up",
            ["<C-g>"] = "preview-page-down",
            ["<C-f>"]   = "preview-page-up",
          },
          fzf = {
            ["ctrl-u"]     = "half-page-up",
            ["ctrl-d"]     = "half-page-down",
            ["shift-down"] = "preview-page-down",
            ["shift-up"]   = "preview-page-up",
            ["ctrl-g"]     = "preview-page-down",
            ["ctrl-f"]     = "preview-page-up",
          },
        },
        files = {
          prompt = 'Files❯ ',
          multiprocess = true,
          git_icons = true,
          file_icons = true,
          color_icons = true,
          cmd = 'rg --files --hidden --no-ignore-vcs --ignore-file ~/.config/nvim/.rgignore',
          previewer = 'builtin',
        },
        grep = {
          prompt = 'Rg❯ ',
          input_prompt = 'Grep For❯ ',
          multiprocess = true,
          git_icons = true,
          file_icons = true,
          color_icons = true,
          cmd = 'rg --color=always --column --hidden -n --no-heading -S --no-ignore-vcs --ignore-file ~/.config/nvim/.rgignore',
          previewer = 'builtin',
        },
        -- Disable find command usage to avoid macOS compatibility issues
        find = {
          cmd = 'rg --files --hidden --no-ignore-vcs --ignore-file ~/.config/nvim/.rgignore',
        },
        -- Ensure LSP operations work properly
        lsp = {
          code_actions    = { previewer = 'builtin' },
          implementations = { previewer = 'builtin' },
          references      = { previewer = 'builtin' },
          definitions     = { previewer = 'builtin' },
        },
      })
    end,
  },

  -- Notification system
  {
    'rcarriga/nvim-notify',
    config = function()
      local hl = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
      local bg = hl and hl.bg and string.format('#%06x', hl.bg) or '#000000'
      require('notify').setup({
        background_colour = bg,
        render = 'wrapped-compact',
        stages = 'fade',
        timeout = 3000,
      })
      vim.notify = require('notify')
    end,
  },

  -- Noice: unified UI for cmdline, messages, LSP hover, signature help, diagnostics
  {
    'folke/noice.nvim',
    dependencies = {
      'MunifTanjim/nui.nvim',
      'rcarriga/nvim-notify',
    },
    config = function()
      require('noice').setup({
        lsp = {
          -- Let noice handle hover and signature help
          hover    = { enabled = true },
          signature = { enabled = true },
          -- Override markdown rendering so cmp + other plugins use Treesitter
          override = {
            ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
            ['vim.lsp.util.stylize_markdown'] = true,
            ['cmp.entry.get_documentation'] = true,
          },
        },
        cmdline = {
          view = 'cmdline_popup',
        },
        views = {
          cmdline_popup = {
            position = { row = '35%', col = '50%' },
            size = { width = 60, height = 'auto' },
          },
          popupmenu = {
            relative = 'editor',
            position = { row = '45%', col = '50%' },
            size = { width = 60, height = 10 },
            border = { style = 'rounded', padding = { 0, 1 } },
          },
        },
        presets = {
          bottom_search        = true,   -- classic bottom cmdline for search
          command_palette      = false,  -- we manage positions manually
          long_message_to_split = true,  -- long messages go to a split
          lsp_doc_border       = true,   -- border on hover/signature docs
        },
      })
    end,
  },

  -- Other UI plugins
  { 'ryanoasis/vim-devicons' },
  { 'edkolev/tmuxline.vim' },
  { 'frazrepo/vim-rainbow' },
}

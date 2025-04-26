vim.opt.relativenumber = true
vim.o.timeoutlen = 0
vim.opt.shada = { "'100", "<50", "s10", "h" }
vim.opt.shiftwidth = 4;
vim.opt.tabstop = 4;

vim.opt.tabstop = 4       -- Width of a \t character (display)
vim.opt.shiftwidth = 4    -- Indent size for `>>`, `<<`, auto-indent
vim.opt.softtabstop = 4   -- Spaces inserted when pressing <Tab>
vim.opt.expandtab = true  -- Convert tabs to spaces

lvim.keys.normal_mode["m"] = ":write<CR>"
lvim.keys.normal_mode["S"] = ":HopWordCurrentLine<CR>"

lvim.keys.normal_mode["<TAB>"] = ":BufferLineCycleNext<CR>"
lvim.keys.normal_mode["<S-TAB>"] = ":BufferLineCyclePrev<CR>"

lvim.builtin.telescope.theme = "center"
lvim.builtin.gitsigns.opts.current_line_blame_opts.delay = 250
lvim.builtin.gitsigns.opts.current_line_blame = true
lvim.builtin.gitsigns.opts.current_line_blame_opts.virt_text_pos = 'right_align'
local width = math.floor(vim.o.columns * 0.5)  -- 70% of screen width
local height = math.floor(vim.o.lines * 0.9)   -- 70% of screen height

lvim.builtin.nvimtree.setup.view.float.enable = true
lvim.builtin.nvimtree.setup.view.float.open_win_config.width = width;
lvim.builtin.nvimtree.setup.view.float.open_win_config.height = height;

lvim.builtin.nvimtree.setup.view.float.open_win_config.row = (vim.o.lines - height) / 2;
lvim.builtin.nvimtree.setup.view.float.open_win_config.col = (vim.o.columns - width) / 2;

lvim.builtin.which_key.mappings["f"] = {
  name = "Find",
  f = { ":Telescope find_files<cr>", "Find Files" },
  d = { ":Telescope live_grep<cr>", "Live Grep" },
  g = { ":Telescope git_status<cr>", "Live Grep" },
}

lvim.builtin.which_key.mappings["c"] = {
  name = "Buffer Close",
  o = { ":BufferLineCloseOthers<cr>", "Close Others" },
  c = { ":BufferKill<cr>", "Close Current" },
  l = { ":BufferLineCloseLeft<cr>", "Close Left" },
  r = { ":BufferLineCloseRight<cr>", "Close Right" },
  w = { ":close<cr>", "Close Window" },
}

lvim.builtin.which_key.mappings["l"] = {
  name = "LSP",
  a = { "<cmd>lua vim.lsp.buf.code_action()<cr>", "Code Action" },
  d = { "<cmd>Telescope diagnostics bufnr=0 theme=get_ivy<cr>", "Buffer Diagnostics" },
  w = { "<cmd>Telescope diagnostics<cr>", "Diagnostics" },
  f = { "<cmd>lua require('lvim.lsp.utils').format()<cr>", "Format" },
  i = { "<cmd>LspInfo<cr>", "Info" },
  I = { "<cmd>Mason<cr>", "Mason Info" },
  j = {
    "<cmd>lua vim.diagnostic.goto_next()<cr>",
    "Next Diagnostic",
  },
  k = {
    "<cmd>lua vim.diagnostic.goto_prev()<cr>",
    "Prev Diagnostic",
  },
  l = { "<cmd>lua vim.lsp.codelens.run()<cr>", "CodeLens Action" },
  q = { "<cmd>lua vim.diagnostic.setloclist()<cr>", "Quickfix" },
  r = { "<cmd>lua vim.lsp.buf.rename()<cr>", "Rename" },
  s = { "<cmd>Telescope lsp_document_symbols<cr>", "Document Symbols" },
  S = {
    "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>",
    "Workspace Symbols",
  },
  e = { "<cmd>Telescope quickfix<cr>", "Telescope Quickfix" },
  g = { ":Lspsaga peek_definition<cr>", "Peek Defintion" },
  h = { ":Lspsaga goto_definition<cr>", "Goto Definition" },
  m = { ":Lspsaga diagnostic_jump_next<cr>", "Diagnostic Jump Next" },
  n = { ":Lspsaga hover_doc<cr>", "Hover Doc" },
  v = { ":Lspsaga finder<cr>", "Hover Doc" },
}

local formatters = require "lvim.lsp.null-ls.formatters"
formatters.setup {
  {
    name = "clang_format",
    args = { 
      "-style={BasedOnStyle: Google, IndentWidth: 4}"  -- Replace `Google` with `LLVM`, `Chromium`, etc.
    },
    filetypes = { "cpp" },
  }
}

lvim.plugins = {
  -- Shows color preview for hexdecimal numbers in text
  {
    'norcalli/nvim-colorizer.lua'
  },

  -- Jump to words in text
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    -- stylua: ignore
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
    },
  },

  -- Jump to words in text
  {
    'ggandor/leap.nvim'
  },

  -- Catppuccin theme
  {
    'catppuccin/nvim'
  },

  -- Extends LSP capabilities
  {
    'nvimdev/lspsaga.nvim',
    config = function()
      require('lspsaga').setup({
        symbol_in_winbar = {
          enable = false,
        }
      })
    end,
    dependencies = {
      'nvim-treesitter/nvim-treesitter', -- optional
      'nvim-tree/nvim-web-devicons',     -- optional
    },
  },

  -- Used for jumping to word in line
  {
    'hadronized/hop.nvim',
    config = function()
      require('hop').setup({
        keys = 'asdfjkl;'
      })
    end
  },

  -- Autoupdates imports on edit
  {
    "antosha417/nvim-lsp-file-operations",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-tree.lua",
    },
    config = function()
      require("lsp-file-operations").setup()
    end,
  },

  -- Catppuccin theme
  {
    'jay-babu/mason-nvim-dap.nvim',
    event = "VeryLazy",
    config = function()
      require("mason").setup()
      require("mason-nvim-dap").setup()
      -- DAP Configuration for C++
      local dap = require('dap')
      -- Ensure you have codelldb installed via mason
      require('mason-nvim-dap').setup({
        ensure_installed = { 'codelldb' },
      })
      local codelldb_path = vim.fn.stdpath('data') .. '/mason/bin/codelldb'
      -- Add configuration for C++
      dap.adapters.codelldb = {
        type = 'server',
        port = 13000,
        executable = {
          command = codelldb_path, -- This is where the codelldb binary is located, replace with actual path
          args = { '--port', '13000' }
        }
      }
      dap.configurations.cpp = {
        {
          name = "Launch file", -- This is the configuration name
          type = "codelldb",    -- This will tell DAP to use the codelldb adapter
          request = "launch",
          program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
          end,
          cwd = '${workspaceFolder}', -- The working directory for the debug session
          stopAtEntry = false,
          args = {},
        }
      }
      dap.configurations.c = dap.configurations.cpp -- Use the same config for C if you want
    end,
    opts = {
      handlers = {},
      ensure_installed = {
        "codelldb"
      }
    }
  },
  {
    "chentoast/marks.nvim",
    event = "VeryLazy",
    opts = {},
    config = function()
      require("marks").setup({
        default_mappings = false,
        force_write_shada = true
      })
    end
  },

  {
    "mg979/vim-visual-multi"
  }

  --
  -- {
  --   'Civitasv/cmake-tools.nvim',
  --   osys = require("cmake-tools.osys");
  --   require("cmake-tools").setup {
  --     cmake_command = "cmake",                                      -- this is used to specify cmake command path
  --     ctest_command = "ctest",                                      -- this is used to specify ctest command path
  --     cmake_use_preset = true,
  --     cmake_regenerate_on_save = true,                              -- auto generate when save CMakeLists.txt
  --     cmake_generate_options = { "-DCMAKE_EXPORT_COMPILE_COMMANDS=1" }, -- this will be passed when invoke `CMakeGenerate`
  --     cmake_build_options = {},                                     -- this will be passed when invoke `CMakeBuild`
  --     -- support macro expansion:
  --     --       ${kit}
  --     --       ${kitGenerator}
  --     --       ${variant:xx}
  --     cmake_build_directory = function()
  --       if osys.iswin32 then
  --         return "out\\${variant:buildType}"
  --       end
  --       return "out/${variant:buildType}"
  --     end,                                   -- this is used to specify generate directory for cmake, allows macro expansion, can be a string or a function returning the string, relative to cwd.
  --     cmake_soft_link_compile_commands = true, -- this will automatically make a soft link from compile commands file to project root dir
  --     cmake_compile_commands_from_lsp = false, -- this will automatically set compile commands file location using lsp, to use it, please set `cmake_soft_link_compile_commands` to false
  --     cmake_kits_path = nil,                 -- this is used to specify global cmake kits path, see CMakeKits for detailed usage
  --     cmake_variants_message = {
  --       short = { show = true },             -- whether to show short message
  --       long = { show = true, max_length = 40 }, -- whether to show long message
  --     },
  --     cmake_dap_configuration = {            -- debug settings for cmake
  --       name = "cpp",
  --       type = "codelldb",
  --       request = "launch",
  --       stopOnEntry = false,
  --       runInTerminal = true,
  --       console = "integratedTerminal",
  --     },
  --     cmake_executor = {                -- executor to use
  --       name = "quickfix",              -- name of the executor
  --       opts = {},                      -- the options the executor will get, possible values depend on the executor type. See `default_opts` for possible values.
  --       default_opts = {                -- a list of default and possible values for executors
  --         quickfix = {
  --           show = "always",            -- "always", "only_on_error"
  --           position = "belowright",    -- "vertical", "horizontal", "leftabove", "aboveleft", "rightbelow", "belowright", "topleft", "botright", use `:h vertical` for example to see help on them
  --           size = 10,
  --           encoding = "utf-8",         -- if encoding is not "utf-8", it will be converted to "utf-8" using `vim.fn.iconv`
  --           auto_close_when_success = true, -- typically, you can use it with the "always" option; it will auto-close the quickfix buffer if the execution is successful.
  --         },
  --         toggleterm = {
  --           direction = "float", -- 'vertical' | 'horizontal' | 'tab' | 'float'
  --           close_on_exit = false, -- whether close the terminal when exit
  --           auto_scroll = true, -- whether auto scroll to the bottom
  --           singleton = true,  -- single instance, autocloses the opened one, if present
  --         },
  --         overseer = {
  --           new_task_opts = {
  --             strategy = {
  --               "toggleterm",
  --               direction = "horizontal",
  --               autos_croll = true,
  --               quit_on_exit = "success"
  --             }
  --           }, -- options to pass into the `overseer.new_task` command
  --           on_new_task = function(task)
  --             require("overseer").open(
  --               { enter = false, direction = "right" }
  --             )
  --           end, -- a function that gets overseer.Task when it is created, before calling `task:start`
  --         },
  --         terminal = {
  --           name = "Main Terminal",
  --           prefix_name = "[CMakeTools]: ", -- This must be included and must be unique, otherwise the terminals will not work. Do not use a simple spacebar " ", or any generic name
  --           split_direction = "horizontal", -- "horizontal", "vertical"
  --           split_size = 11,

  --           -- Window handling
  --           single_terminal_per_instance = true, -- Single viewport, multiple windows
  --           single_terminal_per_tab = true,   -- Single viewport per tab
  --           keep_terminal_static_location = true, -- Static location of the viewport if avialable
  --           auto_resize = true,               -- Resize the terminal if it already exists

  --           -- Running Tasks
  --           start_insert = false,   -- If you want to enter terminal with :startinsert upon using :CMakeRun
  --           focus = false,          -- Focus on terminal when cmake task is launched.
  --           do_not_add_newline = false, -- Do not hit enter on the command inserted when using :CMakeRun, allowing a chance to review or modify the command before hitting enter.
  --         },                        -- terminal executor uses the values in cmake_terminal
  --       },
  --     },
  --     cmake_runner = {           -- runner to use
  --       name = "terminal",       -- name of the runner
  --       opts = {},               -- the options the runner will get, possible values depend on the runner type. See `default_opts` for possible values.
  --       default_opts = {         -- a list of default and possible values for runners
  --         quickfix = {
  --           show = "always",     -- "always", "only_on_error"
  --           position = "belowright", -- "bottom", "top"
  --           size = 10,
  --           encoding = "utf-8",
  --           auto_close_when_success = true, -- typically, you can use it with the "always" option; it will auto-close the quickfix buffer if the execution is successful.
  --         },
  --         toggleterm = {
  --           direction = "float", -- 'vertical' | 'horizontal' | 'tab' | 'float'
  --           close_on_exit = false, -- whether close the terminal when exit
  --           auto_scroll = true, -- whether auto scroll to the bottom
  --           singleton = true,  -- single instance, autocloses the opened one, if present
  --         },
  --         overseer = {
  --           new_task_opts = {
  --             strategy = {
  --               "toggleterm",
  --               direction = "horizontal",
  --               autos_croll = true,
  --               quit_on_exit = "success"
  --             }
  --           }, -- options to pass into the `overseer.new_task` command
  --           on_new_task = function(task)
  --           end, -- a function that gets overseer.Task when it is created, before calling `task:start`
  --         },
  --         terminal = {
  --           name = "Main Terminal",
  --           prefix_name = "[CMakeTools]: ", -- This must be included and must be unique, otherwise the terminals will not work. Do not use a simple spacebar " ", or any generic name
  --           split_direction = "horizontal", -- "horizontal", "vertical"
  --           split_size = 11,

  --           -- Window handling
  --           single_terminal_per_instance = true, -- Single viewport, multiple windows
  --           single_terminal_per_tab = true,   -- Single viewport per tab
  --           keep_terminal_static_location = true, -- Static location of the viewport if avialable
  --           auto_resize = true,               -- Resize the terminal if it already exists

  --           -- Running Tasks
  --           start_insert = false,   -- If you want to enter terminal with :startinsert upon using :CMakeRun
  --           focus = false,          -- Focus on terminal when cmake task is launched.
  --           do_not_add_newline = false, -- Do not hit enter on the command inserted when using :CMakeRun, allowing a chance to review or modify the command before hitting enter.
  --         },
  --       },
  --     },
  --     cmake_notifications = {
  --       runner = { enabled = true },
  --       executor = { enabled = true },
  --       spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }, -- icons used for progress display
  --       refresh_rate_ms = 100, -- how often to iterate icons
  --     },
  --     cmake_virtual_text_support = true, -- Show the target related to current file using virtual text (at right corner)
  --   }
  -- }
}

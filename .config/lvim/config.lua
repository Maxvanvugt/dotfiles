vim.opt.relativenumber = true
vim.o.timeoutlen = 0
vim.opt.shada = { "'100", "<50", "s10", "h" }

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
  }
}

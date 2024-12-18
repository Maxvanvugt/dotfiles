vim.opt.relativenumber = true
vim.o.timeoutlen = 0

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

lvim.builtin.which_key.mappings["j"] = {
  name = "LSP Saga",
  f = { ":Lspsaga peek_definition<cr>", "Peek Defintion" },
  d = { ":Lspsaga goto_definition<cr>", "Goto Definition" },
  s = { ":Lspsaga diagnostic_jump_next<cr>", "Diagnostic Jump Next" },
  a = { ":Lspsaga hover_doc<cr>", "Hover Doc" },
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
  }
}

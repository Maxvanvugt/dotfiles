vim.opt.relativenumber = true

lvim.keys.normal_mode["m"] = ":write<CR>"

lvim.keys.normal_mode["<TAB>"] = ":BufferLineCycleNext<CR>"
lvim.keys.normal_mode["<S-TAB>"] = ":BufferLineCyclePrev<CR>"

-- lvim.transparent_window = true

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
  s = { ":Lspsaga diagnostic_jump_next<cr>", "Diagnostic Jump Next" },
  d = { ":Lspsaga hover_doc<cr>", "Hover Doc" }
}

lvim.builtin.which_key.mappings["k"] = {
  name = "Git Signs",
  f = { ":Gitsigns next_hunk<cr>", "Next Hunk" },
  d = { ":Gitsigns toggle_current_line_blame<cr>", "Toggle Current Line Blame" },
}

lvim.builtin.telescope.theme = "center"

lvim.plugins = {
  {
    'norcalli/nvim-colorizer.lua'
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    -- stylua: ignore
    keys = {
      { "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
      { "S",     mode = { "n", "x", "o" }, function() require("flash").treesitter() end,        desc = "Flash Treesitter" }
    },
  },
  {
    'ggandor/leap.nvim'
  },
  {
    'catppuccin/nvim'
  },
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
  }

}

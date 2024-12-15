vim.opt.number = true

lvim.keys.normal_mode["<TAB>"] = ":BufferLineCycleNext<CR>"
lvim.keys.normal_mode["<S-TAB>"] = ":BufferLineCyclePrev<CR>"

lvim.keys.normal_mode["m"] = ":HopWord<CR>"

lvim.builtin.which_key.mappings["f"] = {
  name = "Find",
  f = { ":Telescope find_files<cr>", "Find Files" },
  d = { ":Telescope live_grep<cr>", "Live Grep" },
}

lvim.plugins = {
  {
    'smoka7/hop.nvim',
    opts = {
      keys = 'asdfjkl'
    }
  }
}

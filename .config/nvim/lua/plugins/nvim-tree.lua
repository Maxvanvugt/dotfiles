return {
	"nvim-tree/nvim-tree.lua",
	lazy = false,
	config = function()
		require("nvim-tree").setup({
			filters = {
				dotfiles = false,
			},
			view = {
				adaptive_size = true,
			},
      update_focused_file = {
        enable = true,
        update_root = false,
        ignore_list = {},
      }
		})
	end,
}

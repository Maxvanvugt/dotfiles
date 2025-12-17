-- TODO: Replace with mini.files
return {
	"nvim-tree/nvim-tree.lua",
	version = "*",
	lazy = false,
	dependencies = {
		"nvim-tree/nvim-web-devicons",
	},

	config = function()
		local width = math.floor(vim.o.columns * 0.5) -- 70% of screen width
		local height = math.floor(vim.o.lines * 0.9) -- 70% of screen height
		require("nvim-tree").setup({
			view = {
				float = {
					enable = true,
					open_win_config = {
						relative = "editor",
						width = width,
						height = height,
						row = ((vim.o.lines - height) / 2) - 2,
						col = (vim.o.columns - width) / 2,
						border = "rounded",
					},
				},
			},
		})
	end,
}

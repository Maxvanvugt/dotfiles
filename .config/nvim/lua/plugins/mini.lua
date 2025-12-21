return {
	"nvim-mini/mini.nvim",
	version = "*",
	dependencies = {
		"nvim-tree/nvim-web-devicons",
	},
	config = function()
		require("mini.ai").setup()
		require("mini.files").setup()
		require("mini.surround").setup()
		require("mini.tabline").setup()
		require("mini.diff").setup()
		require("mini.pairs").setup()
		require("mini.files").setup()
		require("mini.bufremove").setup()
		require("mini.git").setup()
		-- TODO: This module causes blinking in statusbar
		require("mini.completion").setup()
		require("mini.colors").setup()
		require("mini.move").setup()
		require("mini.pick").setup()
		require("mini.colors").setup()
		require("mini.statusline").setup()
		require("mini.indentscope").setup()
		require("mini.align").setup()

		require("mini.sessions").setup({
			directory = "~/.local/state/nvim/sessions",
			file = "",
		})

		require("mini.clue").setup({
			triggers = {
				{ mode = "n", keys = "<Leader>" },
				{ mode = "x", keys = "<Leader>" },
			},
			window = {
				delay = 0,
				config = {
					width = vim.o.columns - 50,
					col = vim.o.columns - 25,
				},
			},
			clues = {
				{ mode = "n", keys = "<leader>g", desc = "Git" },
				{ mode = "n", keys = "<leader>l", desc = "LSP" },
				{ mode = "n", keys = "<leader>c", desc = "Close" },
				{ mode = "n", keys = "<leader>f", desc = "Find" },
			},
		})
	end,
}

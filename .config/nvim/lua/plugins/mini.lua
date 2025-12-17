return {
	"nvim-mini/mini.nvim",
	version = "*",
	config = function()
		require("mini.ai").setup()
		require("mini.files").setup()
		require("mini.surround").setup()
		require("mini.tabline").setup()
		require("mini.sessions").setup()
		require("mini.diff").setup()
		-- TODO: This module causes blinking in statusbar
		require("mini.completion").setup()
		require("mini.colors").setup()

		local win_width = 60
		local win_height = 10

		require("mini.clue").setup({
			triggers = {
				-- Leader triggers
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
		})
	end,
}

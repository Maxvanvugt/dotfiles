return {
	"nvim-mini/mini.nvim",
	version = "*",

	config = function()
		require("mini.ai").setup()
		require("mini.clue").setup()
	end,
}

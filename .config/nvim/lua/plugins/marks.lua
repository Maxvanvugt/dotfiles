return {
	"chentoast/marks.nvim",
	event = "VeryLazy",
	opts = {},
	config = function()
		require("marks").setup({
			default_mappings = false,
			force_write_shada = true
		})
	end
}

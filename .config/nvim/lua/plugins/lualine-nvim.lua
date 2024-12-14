local config = function()
	require("lualine").setup({
		options = {
			theme = "dracula",
			globalstatus = true,
			component_separators = { left = "|", right = "|" },
			section_separators = { left = "", right = "" },
		},

		sections = {
			lualine_a = { "mode" },
			lualine_x = { "encoding", "fileformat" },
			lualine_z = { "searchcount" },
		},
		tabline = {},
	})
end

return {
	"nvim-lualine/lualine.nvim",
	lazy = false,
	config = config,
}

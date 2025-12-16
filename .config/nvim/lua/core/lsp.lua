vim.lsp.enable({
	"lua_ls",
})

vim.diagnostic.config({
	virtual_lines = true,
	-- virtual_text = true,
	signs = false,
	underline = true,
	update_in_insert = false,
	severity_sort = true,
	float = {
		border = "rounded",
		header = "",
		prefix = "",
	},
})

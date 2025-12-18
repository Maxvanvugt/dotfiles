require("core.lazy")

vim.lsp.enable("ts_ls")

vim.cmd("colorscheme wildcharm")

vim.opt.cursorline = true
vim.opt.number = true
vim.opt.swapfile = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.clipboard = "unnamedplus"
vim.opt.hidden = true

-- Write
vim.keymap.set("n", "m", ":write<CR>", { desc = "Write file" })

-- Navigate tabs
vim.keymap.set("n", "<TAB>", "]b", { remap = true, desc = "Next tab" })
vim.keymap.set("n", "<S-TAB>", "[b", { remap = true, desc = "Previous tab" })
vim.keymap.set("n", "<leader>co", "<cmd>%bd!|e#|bd#<cr>", { desc = "Close others" })

-- Move lines
vim.keymap.set("v", "<", "<gv", { noremap = true, silent = true, desc = "Move lines to right" })
vim.keymap.set("v", ">", ">gv", { noremap = true, silent = true, desc = "Move lines to left" })

-- Toggle comment
vim.keymap.set("n", "<leader>/", "gcc", { desc = "Toggle comment", remap = true })
vim.keymap.set("v", "<leader>/", "gc", { desc = "Toggle comment", remap = true })

-- File tree toggle
vim.keymap.set("n", "<leader>e", "<cmd>lua MiniFiles.open()<cr>", { desc = "Explorer", remap = true })

-- LSP
vim.keymap.set("n", "<leader>ln", "<cmd>lua vim.lsp.buf.rename()<cr>", { desc = "Rename" })
vim.keymap.set("n", "<leader>la", "<cmd>lua vim.lsp.buf.code_action()<cr>", { desc = "Code action" })
vim.keymap.set("n", "<leader>lr", "<cmd>lua vim.lsp.buf.references()<cr>", { desc = "References" })
vim.keymap.set("n", "<leader>li", "<cmd>lua vim.lsp.buf.implementation()<cr>", { desc = "Implementation" })

-- Window
vim.keymap.set("n", "<C-j>", "<C-w>j", { remap = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { remap = true })
vim.keymap.set("n", "<C-h>", "<C-w>h", { remap = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { remap = true })

-- Wrap visual selection in quotes
vim.keymap.set("v", "'", [[c''<esc>P]], { desc = "Wrap in single quotes" })
vim.keymap.set("v", '"', [[c""<esc>P]], { desc = "Wrap in double quotes" })

-- Wrap selection in double quotes immediately
vim.keymap.set("x", '<leader>"', function()
	require("mini.surround").add("visual")
	vim.schedule(function()
		vim.api.nvim_input('"')
	end)
end, { desc = "Surround with double quotes" })

-- Git
vim.keymap.set(
	"n",
	"<leader>gt",
	"<cmd>lua MiniDiff.toggle_overlay()<cr>",
	{ desc = "Toggle diff overlay", remap = true }
)
vim.keymap.set("n", "<leader>gn", "<cmd>lua MiniDiff.goto_hunk('next')<cr>", { desc = "Goto next hunk", remap = true })
vim.keymap.set(
	"n",
	"<leader>gp",
	"<cmd>lua MiniDiff.goto_hunk('prev')<cr>",
	{ desc = "Goto previous hunk", remap = true }
)
vim.keymap.set("n", "<leader>gg", "<cmd>LazyGit<cr>", { desc = "Open lazygit", remap = true })

-- Flash
vim.keymap.set("n", ";", "<cmd>lua require('flash').jump()<cr>", { desc = "Goto word", remap = true, nowait = true })

-- Buffers
vim.keymap.set("n", "<leader>co", require("core.functions").close_other_buffers, { desc = "Close other buffers" })
vim.keymap.set("n", "<leader>cc", "<cmd>lua MiniBufremove.delete()<cr>", { desc = "Close current buffer" })

local notify = vim.notify
vim.notify = function(msg, level, opts)
	-- Only show errors (vim.log.levels.ERROR)
	if level ~= vim.log.levels.ERROR then
		return
	end
	notify(msg, level, opts)
end

vim.diagnostic.config({
	virtual_text = true,
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

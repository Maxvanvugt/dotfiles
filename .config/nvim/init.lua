require("core.lazy")

vim.lsp.enable("ts_ ls")
vim.lsp.enable("angularls")
-- vim.lsp.enable("lua_ls")

vim.cmd("colorscheme tokyonight-night")
vim.cmd("set ignorecase")

vim.notify = require("core.functions").notify

vim.api.nvim_set_hl(0, 'FloatBorder', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'FloatTitle', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'DiagnosticFloatingWarn', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'DiagnosticFloatingHint', { bg = 'NONE' })

vim.opt.cursorline = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.swapfile = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.clipboard = "unnamedplus"
vim.opt.hidden = true
vim.opt.termguicolors = true

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

vim.api.nvim_create_autocmd("TextYankPost", {
    callback = function()
        vim.highlight.on_yank()
    end,
})


-- Navigate tabs
vim.keymap.set("n", "<TAB>", "]b", { remap = true, desc = "Next tab" })
vim.keymap.set("n", "<S-TAB>", "[b", { remap = true, desc = "Previous tab" })

-- Move lines
vim.keymap.set("v", "<", "<gv", { noremap = true, silent = true, desc = "Move lines to right" })
vim.keymap.set("v", ">", ">gv", { noremap = true, silent = true, desc = "Move lines to left" })

-- Toggle comment
vim.keymap.set("n", "<leader>/", "gcc", { desc = "Toggle comment", remap = true })
vim.keymap.set("v", "<leader>/", "gc", { desc = "Toggle comment", remap = true })

-- LSP
vim.keymap.set("n", "<leader>lr", "<cmd>lua vim.lsp.buf.rename()<cr>", { desc = "Rename" })
vim.keymap.set("n", "<leader>la", "<cmd>lua vim.lsp.buf.code_action()<cr>", { desc = "Code action" })
vim.keymap.set("n", "<leader>lh", ":Telescope lsp_references<cr>", { desc = "References" })
vim.keymap.set("n", "<leader>li", ":Telescope lsp_implementations<cr>", { desc = "Implementations" })
vim.keymap.set("n", "<leader>ld", ":Telescope lsp_definitions<cr>", { desc = "Definitions" })
vim.keymap.set("n", "<leader>lf", "<cmd>lua vim.lsp.buf.format()<cr>", { desc = "Format" })

-- Window
vim.keymap.set("n", "<C-j>", "<C-w>j", { remap = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { remap = true })
vim.keymap.set("n", "<C-h>", "<C-w>h", { remap = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { remap = true })

-- Wrap visual selection
vim.keymap.set("v", "'", [[c''<esc>P]], { desc = "Wrap in single quotes" })
vim.keymap.set("v", '"', [[c""<esc>P]], { desc = "Wrap in double quotes" })
vim.keymap.set("v", "(", [[c()<esc>P]], { desc = "Wrap in brackets" })
vim.keymap.set("v", "[", [[c{}<esc>P]], { desc = "Wrap in curly brackets", nowait = true })
vim.keymap.set("v", "]", [[c[]<esc>P]], { desc = "Wrap in square brackets", nowait = true })

-- Git
vim.keymap.set("n", "<leader>gt", "<cmd>lua MiniDiff.toggle_overlay()<cr>", { desc = "Toggle diff overlay", remap = true })
vim.keymap.set("n", "<leader>gn", "<cmd>lua MiniDiff.goto_hunk('next')<cr>", { desc = "Goto next hunk", remap = true })
vim.keymap.set("n", "<leader>gp", "<cmd>lua MiniDiff.goto_hunk('prev')<cr>", { desc = "Goto previous hunk", remap = true })
vim.keymap.set("n", "<leader>gg", "<cmd>lua Snacks.lazygit()<cr>", { desc = "Open lazygit", remap = true })

-- Close
vim.keymap.set("n", "<leader>co", require("core.functions").close_other_buffers, { desc = "Close other buffers" })
vim.keymap.set("n", "<leader>cc", "<cmd>lua MiniBufremove.delete()<cr>", { desc = "Close current buffer" })
vim.keymap.set("n", "<leader>cw", "<cmd>close<cr>", { desc = "Close current window" })

-- Telescope
vim.keymap.set("n", "<leader>ff", ":Telescope find_files<cr>", { desc = "Find files" })
vim.keymap.set("n", "<leader>fd", ":Telescope live_grep<cr>", { desc = "Live grep" })
vim.keymap.set("n", "<leader>fg", ":Telescope git_status<cr>", { desc = "Git status" })

-- Other
vim.keymap.set("n", ";", "<cmd>lua require('flash').jump()<cr>", { desc = "Goto word", remap = true, nowait = true })
vim.keymap.set("n", "<leader>h", "<cmd>nohlsearch<cr>", { desc = "Remove highlight search" })
vim.keymap.set("n", "m", ":write<CR>", { desc = "Write file" })
vim.keymap.set("n", "<leader>e", "<cmd>lua MiniFiles.open()<cr>", { desc = "Open explorer", remap = true })
vim.keymap.set("v", ";", "<cmd>lua vim.cmd('normal iq')<cr>", { desc = "Move to next quotes when in visual mode" })
vim.keymap.set("v", ".", "<cmd>lua vim.cmd('normal ia')<cr>", { desc = "Move to next quotes when in visual mode" })

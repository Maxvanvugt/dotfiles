require("core.lazy")
require("core.lsp")

require("mason").setup()

vim.opt.cursorline = true
vim.opt.number = true
vim.opt.swapfile = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.clipboard = "unnamedplus"
vim.keymap.set("n", "m", ":write<CR>", { desc = "Write file" })
vim.keymap.set("n", "<TAB>", ":BufferNext<CR>", { desc = "Next tab" })
vim.keymap.set("n", "<S-TAB>", ":BufferPrevious<CR>", { desc = "Previous tab" })
vim.keymap.set("v", "<", "<gv", { noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { noremap = true, silent = true })

vim.keymap.set("n", "<leader>/", "gcc", { desc = "Toggle comment", remap = true })
vim.keymap.set("v", "<leader>/", "gc<cmd>normal! gv<cr>", { desc = "Toggle comment", remap = true })

vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "Explorer", remap = true })

require("telescope").setup({
    defaults = {
        file_ignore_patterns = { "node_modules" },
    },
})

require("lspsaga").setup({
    ui = {
        code_action = "",
    },
})

require("gitsigns").setup({
    current_line_blame = true,
    current_line_blame_opts = {
        delay = 250,
        virt_text_pos = "right_align",
    },
})

require("snacks").setup({
    lazygit = {
        configure = true,
    },
})

require("flash").setup({})

require("oil").setup()

require("mason").setup({})

require("nvim-treesitter").setup({
    ensure_installed = {
        "lua",
        "typescript",
        "html",
        "css",
        "scss",
        "javascript",
    },
    highlight = {
        enable = true,
    },
    indent = {
        enable = true,
    },
})

require("mini.ai").setup()
require("mini.surround").setup()
require("mini.tabline").setup()
require("mini.diff").setup()
require("mini.pairs").setup()
require("mini.files").setup()
require("mini.bufremove").setup()
require("mini.git").setup()
require("mini.completion").setup()
require("mini.colors").setup()
require("mini.move").setup()
require("mini.pick").setup()
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
        { mode = "n", keys = "<leader>x", desc = "Checkbox" },
        { mode = "n", keys = "<leader>t", desc = "Toggle" },
        { mode = "n", keys = "<leader>e", desc = "Explorer" },
    },
})

vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
        require("dashboard").setup({
            config = {
                week_header = {
                    enable = true,
                },
            },
        })
        require("marks").setup({
            default_mappings = false,
            force_write_shada = true,
        })
    end,
})

vim.api.nvim_create_autocmd("FileType", {
    pattern = "lua",
    once = true,
    callback = function()
        require("lazydev").setup({
            library = {
                { path = "${3rd}/luv/library", words = { "vim%.uv" } },
            },
        })
    end,
})

-- Native plugin manager: :help vim.pack
vim.pack.add({
    { src = "https://github.com/nvim-lua/plenary.nvim" },
    { src = "https://github.com/nvim-tree/nvim-web-devicons" },
    { src = "https://github.com/folke/tokyonight.nvim" },
    {
        src = "https://github.com/nvim-treesitter/nvim-treesitter",
        -- Legacy master/v0.10 line is incompatible with Nvim 0.12 (markdown fenced blocks / injections).
        version = "main",
    },
    { src = "https://github.com/nvim-mini/mini.nvim" },
    {
        src = "https://github.com/nvim-telescope/telescope.nvim",
        version = "v0.2.0",
    },
    { src = "https://github.com/nvimdev/lspsaga.nvim" },
    { src = "https://github.com/nvimdev/dashboard-nvim" },
    { src = "https://github.com/chentoast/marks.nvim" },
    { src = "https://github.com/lewis6991/gitsigns.nvim" },
    { src = "https://github.com/folke/snacks.nvim" },
    { src = "https://github.com/folke/lazydev.nvim" },
    { src = "https://github.com/folke/flash.nvim" },
    { src = "https://github.com/mason-org/mason.nvim" },
    { src = "https://github.com/jake-stewart/multicursor.nvim" },
    { src = "https://github.com/stevearc/oil.nvim" },
    { src = "https://github.com/sindrets/diffview.nvim" },
    { src = "https://github.com/tpope/vim-fugitive" },
}, { load = true, confirm = false })

-- After install/update of nvim-treesitter, refresh parsers (replaces lazy.nvim `build = :TSUpdate`).
vim.api.nvim_create_autocmd("PackChanged", {
    callback = function(ev)
        local name = ev.data.spec.name
        if name ~= "nvim-treesitter" then
            return
        end
        local kind = ev.data.kind
        if kind ~= "install" and kind ~= "update" then
            return
        end
        vim.defer_fn(function()
            pcall(vim.cmd, "TSUpdate")
        end, 100)
    end,
})

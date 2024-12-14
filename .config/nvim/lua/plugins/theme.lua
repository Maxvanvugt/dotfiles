-- return {
-- 	"catppuccin/nvim",
-- 	name = "theme",
-- 	lazy = false,
-- 	priority = 999,
-- 	config = function()
-- 		vim.cmd("colorscheme catppuccin")
-- 		require("catppuccin").setup({})
-- 	end,
-- }

-- return {
-- 	"rebelot/kanagawa.nvim",
-- 	name = "theme",
-- 	lazy = false,
-- 	priority = 999,
-- 	config = function()
-- 		vim.cmd("colorscheme kanagawa")
-- 		require("kanagawa").setup({})
-- 	end,
-- }

-- return {
-- 	"EdenEast/nightfox.nvim",
-- 	name = "theme",
-- 	lazy = false,
-- 	priority = 999,
-- 	config = function()
-- 		vim.cmd("colorscheme nightfox")
-- 		require("nightfox").setup({})
-- 	end,
-- }


return {
  "themercorp/themer.lua",
  lazy = false,
  config = function()
    require("themer").setup({
	  colorscheme = "catppuccin"
    })
  end
}
-- return {
--   "nyoom-engineering/oxocarbon.nvim",
--   name = "theme",
--   lazy = false,
--   priority = 999,
-- 	config = function()
-- 		vim.cmd("colorscheme oxocarbon")
-- 		require("oxocarbon").setup({})
-- 	end,
-- }

-- return {
--   "p00f/alabaster.nvim",
--   name = "theme",
--   lazy = false,
--   priority = 999,
-- 	config = function()
-- 		vim.cmd("colorscheme alabaster")
-- 		require("alabaster").setup({})
-- 	end,
-- }
--
-- return { 'dasupradyumna/midnight.nvim', lazy = false, priority = 1000 }

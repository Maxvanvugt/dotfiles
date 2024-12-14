local keys = {
	{ "<leader>/", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Buffer search" },
	{ "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
	{ "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find All Files" },
	{ "<C-p>", "<cmd>Telescope git_files<cr>", desc = "Git files" },
	{ "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help" },
	{ "<leader>fj", "<cmd>Telescope command_history<cr>", desc = "History" },
	{ "<leader>fk", "<cmd>Telescope keymaps<cr>", desc = "Keymaps" },
	{ "<leader>fl", "<cmd>Telescope lsp_references<cr>", desc = "Lsp References" },
	{ "<leader>fo", "<cmd>Telescope oldfiles<cr>", desc = "Old files" },
	{ "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Ripgrep" },
	{ "<leader>fs", "<cmd>Telescope grep_string<cr>", desc = "Grep String" },
	{ "<leader>ft", "<cmd>Telescope treesitter<cr>", desc = "Treesitter" },
	{ "<leader>fc", "<cmd>Telescope git_status<cr>", desc = "Changed Files" },
	{ "<leader>ft", "<cmd>Telescope themes<cr>", desc = "Themes" },
	{ "<leader>fw", "<cmd>Telescope grep_string<cr>", desc = "Themes" },
}

local conf = require('telescope.config').values;
local actions = require('telescope.actions');

require("telescope").setup({
  defaults = {
    mappings = {
      i = {
        ["<C-w>"] = actions.send_selected_to_qflist,
        ["<C-q>"] = actions.send_to_qflist,
        ["<C-j>"] = "move_selection_next",
        ["<C-k>"] = "move_selection_previous",
        ["<C-Down>"] = "cycle_history_next",
        ["<C-Up>"] = "cycle_history_prev",
      },
    },
    file_ignore_patterns = { "node_modules", ".venv", "dist" },
    layout_config = { width = {padding = 0}, height = {padding = 0}}
  },
  pickers = {
    live_grep = {
      vimgrep_arguments = table.insert(conf.vimgrep_arguments, '--fixed-strings'),
      file_ignore_patterns = { "node_modules", ".venv", "dist" },
      additional_args = function(_)
        return { "--hidden", "--no-ignore-vcs" }
      end,
      hidden = true,
      no_ignore = true,
    },
    find_files = {
      file_ignore_patterns = { "node_modules", ".venv", ".git", "dist" },
      additional_args = function(_)
        return { "--hidden", "--no-ignore-vcs" }
      end,
      no_ignore = true,
      hidden = true,
    },
  },
  extensions = {
    "fzf",
    "themes",
    "git_file_history"
  },
})

require("telescope").load_extension("git_file_history")

return {
	"nvim-telescope/telescope.nvim",
	dependencies = {
		{ "nvim-lua/plenary.nvim" },
		{
			"nvim-telescope/telescope-fzf-native.nvim",
			build = "make",
		},
	},
	keys = keys,
}

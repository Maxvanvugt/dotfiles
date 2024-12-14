-- All LSP related plugins go here
local on_attach = require("util.lsp").on_attach
local diagnostic_signs = require("util.icons").diagnostic_signs
local typescript_organise_imports = require("util.lsp").typescript_organise_imports
local maplazykey = require("util.keymapper").maplazykey

return {
	{
		"glepnir/lspsaga.nvim",
		lazy = false,
		config = function()
			require("lspsaga").setup({
				-- keybinds for navigation in lspsaga window
				move_in_saga = { prev = "<C-k>", next = "<C-j>" },
				-- use enter to open file with finder
				finder_action_keys = {
					open = "<CR>",
				},
				-- use enter to open file with definition preview
				definition_action_keys = {
					edit = "<CR>",
				},
				lightbulb = {
					enable = false,
					sign = false,
				},
				symbol_in_winbar = {
					enable = false,
					sign = false,
				},
			})
		end,
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
		},
	},
	{
		"williamboman/mason-lspconfig.nvim",
		opts = {
			ensure_installed = {
				"efm",
				"bashls",
				"eslint",
				"tsserver",
				"solidity",
				"tailwindcss",
				"pyright",
				"lua_ls",
				"emmet_ls",
				"jsonls",
				"clangd",
			},

			automatic_installation = false,
		},
		event = "BufReadPre",
		dependencies = "williamboman/mason.nvim",
	},
	{
		"williamboman/mason.nvim",
		cmd = "Mason",
		event = "BufReadPre",
		opts = {
			ui = {
				icons = {
					package_installed = "✓",
					package_pending = "➜",
					package_uninstalled = "✗",
				},
			},
		},
	},
	{
		"hrsh7th/nvim-cmp",
		config = function()
			local cmp = require("cmp")
			local lspkind = require("lspkind")

			vim.opt.completeopt = "menu,menuone,noselect"
			cmp.setup({
				mapping = cmp.mapping.preset.insert({
					["<Tab>"] = cmp.mapping.select_next_item(), -- next suggestion
					["<S-Tab>"] = cmp.mapping.select_prev_item(), -- previous suggestion
					["<C-k>"] = cmp.mapping.select_prev_item(), -- previous suggestion
					["<C-j>"] = cmp.mapping.select_next_item(), -- next suggestion
					["<C-b>"] = cmp.mapping.scroll_docs(-4),
					["<C-f>"] = cmp.mapping.scroll_docs(4),
					["<C-Space>"] = cmp.mapping.complete(), -- show completion suggestions
					["<C-e>"] = cmp.mapping.abort(), -- close completion window
					["<CR>"] = cmp.mapping.confirm({ select = false }),
				}),
				-- sources for autocompletion
				sources = cmp.config.sources({
					{ name = "nvim_lsp" }, -- lsp
					{ name = "buffer" }, -- text within current buffer
					{ name = "path" }, -- file system paths
				}),
				-- configure lspkind for vs-code like icons
				formatting = {
					format = lspkind.cmp_format({
						maxwidth = 50,
						ellipsis_char = "...",
					}),
				},
			})
		end,
		dependencies = {
			"onsails/lspkind.nvim",
		},
	},
	{
		"neovim/nvim-lspconfig",
		config = function()
			require("neoconf").setup({})
			-- require("java").setup()
			local cmp_nvim_lsp = require("cmp_nvim_lsp")
			local lspconfig = require("lspconfig")
			local capabilities = cmp_nvim_lsp.default_capabilities()

			for type, icon in pairs(diagnostic_signs) do
				local hl = "DiagnosticSign" .. type
				vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
			end

			-- lua
			lspconfig.lua_ls.setup({
				capabilities = capabilities,
				on_attach = on_attach,
				settings = { -- custom settings for lua
					Lua = {
						-- make the language server recognize "vim" global
						diagnostics = {
							globals = { "vim" },
						},
						workspace = {
							-- make language server aware of runtime files
							library = {
								[vim.fn.expand("$VIMRUNTIME/lua")] = true,
								[vim.fn.stdpath("config") .. "/lua"] = true,
							},
						},
					},
				},
			})

			-- json
			lspconfig.jsonls.setup({
				capabilities = capabilities,
				on_attach = on_attach,
				filetypes = { "json", "jsonc" },
			})

			-- Java
			lspconfig.jdtls.setup({
				capabilities = capabilities,
				on_attach = on_attach,
			})

			-- python
			lspconfig.pyright.setup({
				capabilities = capabilities,
				on_attach = on_attach,
				settings = {
					pyright = {
						disableOrganizeImports = false,
						analysis = {
							useLibraryCodeForTypes = true,
							autoSearchPaths = true,
							diagnosticMode = "workspace",
							autoImportCompletions = true,
						},
					},
				},
			})

			-- typescript
			lspconfig.tsserver.setup({
				on_attach = on_attach,
				capabilities = capabilities,
				filetypes = {
					"typescript",
					"javascript",
					"typescriptreact",
					"javascriptreact",
				},
				commands = {
					TypeScriptOrganizeImports = typescript_organise_imports,
				},
				settings = {
					typescript = {
						indentStyle = "space",
						indentSize = 2,
					},
				},
				root_dir = lspconfig.util.root_pattern("package.json", "tsconfig.json", ".git"),
			})

			-- bash
			lspconfig.bashls.setup({
				capabilities = capabilities,
				on_attach = on_attach,
				filetypes = { "sh", "aliasrc" },
			})

			-- eslint
			lspconfig.eslint.setup({
				capabilities = capabilities,
				on_attach = on_attach,
				filetypes = { "typescript" },
			})

			-- solidity
			lspconfig.solidity.setup({
				capabilities = capabilities,
				on_attach = on_attach,
				filetypes = { "solidity" },
			})

			-- typescriptreact, javascriptreact, css, sass, scss, less, svelte, vue
			lspconfig.emmet_ls.setup({
				capabilities = capabilities,
				on_attach = on_attach,
				filetypes = {
					"typescriptreact",
					"javascriptreact",
					"javascript",
					"css",
					"sass",
					"scss",
					"less",
					"svelte",
					"vue",
					"html",
				},
			})

			-- docker
			lspconfig.dockerls.setup({
				capabilities = capabilities,
				on_attach = on_attach,
			})

			-- C/C++
			lspconfig.clangd.setup({
				capabilities = capabilities,
				on_attach = on_attach,
				cmd = {
					"clangd",
					"--offset-encoding=utf-16",
				},
			})

			local luacheck = require("efmls-configs.linters.luacheck")
			local stylua = require("efmls-configs.formatters.stylua")
			local flake8 = require("efmls-configs.linters.flake8")
			local black = require("efmls-configs.formatters.black")
			local eslint = require("efmls-configs.linters.eslint")
			local eslint_d = require("efmls-configs.linters.eslint_d")
			local prettier_d = require("efmls-configs.formatters.prettier_d")
			local fixjson = require("efmls-configs.formatters.fixjson")
			local shellcheck = require("efmls-configs.linters.shellcheck")
			local shfmt = require("efmls-configs.formatters.shfmt")
			local hadolint = require("efmls-configs.linters.hadolint")
			local solhint = require("efmls-configs.linters.solhint")
			local cpplint = require("efmls-configs.linters.cpplint")
			local clangformat = require("efmls-configs.formatters.clang_format")

			-- configure efm server
			lspconfig.efm.setup({
				filetypes = {
					"lua",
					"python",
					"json",
					"jsonc",
					"sh",
					"javascript",
					"javascriptreact",
					"typescript",
					"typescriptreact",
					"svelte",
					"vue",
					"markdown",
					"docker",
					"solidity",
					"html",
					"css",
					"c",
					"cpp",
				},
				init_options = {
					documentFormatting = true,
					documentRangeFormatting = true,
					hover = true,
					documentSymbol = true,
					codeAction = true,
					completion = true,
				},
				settings = {
					languages = {
						lua = { luacheck, stylua },
						python = { flake8, black },
						typescript = { eslint_d, prettier_d },
						json = { eslint, fixjson },
						jsonc = { eslint, fixjson },
						sh = { shellcheck, shfmt },
						javascript = { eslint, prettier_d },
						javascriptreact = { eslint, prettier_d },
						typescriptreact = { eslint, prettier_d },
						svelte = { eslint, prettier_d },
						vue = { eslint, prettier_d },
						markdown = { prettier_d },
						docker = { hadolint, prettier_d },
						solidity = { solhint },
						html = { prettier_d },
						css = { prettier_d },
						c = { clangformat, cpplint },
						cpp = { clangformat, cpplint },
					},
				},
			})
		end,
		lazy = false,
		dependencies = {
			"windwp/nvim-autopairs",
			"williamboman/mason.nvim",
			"creativenull/efmls-configs-nvim",
			"hrsh7th/nvim-cmp",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-nvim-lsp",
		},
	},
	{
		"folke/trouble.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			signs = {
				-- icons / text used for a diagnostic
				error = diagnostic_signs.Error,
				warning = diagnostic_signs.Warn,
				hint = diagnostic_signs.Hint,
				information = diagnostic_signs.Info,
				other = diagnostic_signs.Info,
			},
		},
		keys = {
			maplazykey("<leader>xx", function()
				require("trouble").toggle()
			end, "Toggle Trouble"),
			maplazykey("<leader>xw", function()
				require("trouble").toggle("workspace_diagnostics")
			end, "Show Workspace Diagnostics"),
			maplazykey("<leader>xd", function()
				require("trouble").toggle("document_diagnostics")
			end, "Show Document Diagnostics"),
			maplazykey("<leader>xq", function()
				require("trouble").toggle("quickfix")
			end, "Toggle Quickfix List"),
			maplazykey("<leader>xl", function()
				require("trouble").toggle("loclist")
			end, "Toggle Location List"),
			maplazykey("gR", function()
				require("trouble").toggle("lsp_references")
			end, "Toggle LSP References"),
		},
	},
	{
		"hrsh7th/cmp-buffer",
	},
	{
		"hrsh7th/cmp-path",
	},
	{
		"hrsh7th/cmp-cmdline",
	},
	{
		"hrsh7th/nvim-cmp",
	},
	{
		"dgagn/diagflow.nvim",
        lazy = false,
		opts = {
            scope = 'line'
        },
	},
}

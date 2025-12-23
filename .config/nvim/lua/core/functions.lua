local M = {}
local notify = vim.notify

function M.close_other_buffers()
	local current_buf = vim.api.nvim_get_current_buf()
	local all_bufs = vim.api.nvim_list_bufs()

	for _, buf in ipairs(all_bufs) do
		if buf ~= current_buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_option(buf, "buflisted") then
			require("mini.bufremove").delete(buf, false)
		end
	end
end

function M.notify(msg, level, opts)
	-- Only show errors (vim.log.levels.ERROR)
	if level ~= vim.log.levels.ERROR then
		return
	end
	notify(msg, level, opts)
end

function M.toggle_cursor_word()
	vim.g.minicursorword_disable = not vim.g.minicursorword_disable
end

function M.toggle_checkbox()
    local original_pos = vim.api.nvim_win_get_cursor(0)

    vim.cmd("normal 0wl")

    local line = vim.fn.getline('.')
    local col = vim.fn.col('.')
    local char = line:sub(col, col)

    if char == 'x' then
        vim.cmd("normal r ")
    else
        vim.cmd("normal rx")
    end

    vim.api.nvim_win_set_cursor(0, original_pos)
end

function M.new_checkbox()
	vim.cmd("normal o- [ ]  ")
	vim.cmd("startinsert")
end

return M

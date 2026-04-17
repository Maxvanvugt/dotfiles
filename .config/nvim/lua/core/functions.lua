local M = {}
local notify = vim.notify

function M.multicursor_match_add_prev()
    require("multicursor-nvim").matchAddCursor(-1)
end

function M.multicursor_match_add_next()
    require("multicursor-nvim").matchAddCursor(1)
end

function M.multicursor_match_skip_prev()
    require("multicursor-nvim").matchSkipCursor(-1)
end

function M.multicursor_match_skip_next()
    require("multicursor-nvim").matchSkipCursor(1)
end

function M.multicursor_prev_cursor()
    require("multicursor-nvim").prevCursor()
end

function M.multicursor_next_cursor()
    require("multicursor-nvim").nextCursor()
end

function M.multicursor_delete_cursor()
    require("multicursor-nvim").deleteCursor()
end

function M.multicursor_toggle_cursors_escape()
    if not require("multicursor-nvim").cursorsEnabled() then
        require("multicursor-nvim").enableCursors()
    else
        require("multicursor-nvim").clearCursors()
    end
end

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
    if level == vim.log.levels.DEBUG then
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

function M.make_mark()
    local mark = vim.fn.input("Enter mark letter: ")
    if mark ~= "" then
        vim.cmd("normal! m" .. mark)
    end
end

function M.toggle_wrap()
    vim.opt.wrap = not vim.opt.wrap:get()
end

function M.toggle_relative_number()
    vim.opt.relativenumber = not vim.opt.relativenumber:get()
end

function M.telescope_grep_ts()
    require("telescope.builtin").live_grep({
        glob_pattern = "*.ts",
    })
end

function M.telescope_grep_json()
    require("telescope.builtin").live_grep({
        glob_pattern = "*.json",
    })
end

function M.telescope_grep_html()
    require("telescope.builtin").live_grep({
        glob_pattern = "*.html",
    })
end

function M.telescope_grep_component()
    require("telescope.builtin").live_grep({
        glob_pattern = "*.component.ts",
    })
end

local function line_blame_commit_hash()
    local result = vim.fn.system(
        "git log -1 --format=%H -L " .. vim.fn.line(".") .. "," .. vim.fn.line(".") .. ":" .. vim.fn.expand("%")
    )
    local hash = result:match("^(%x%x%x%x%x%x%x%x)")
    if not hash then
        return nil, result
    end
    return hash
end

function M.diff_blame()
    local hash, err = line_blame_commit_hash()
    if not hash then
        vim.notify("Could not get commit hash: " .. err, vim.log.levels.ERROR)
        return
    end
    vim.cmd("DiffviewFileHistory --range=" .. hash .. "~.." .. hash)
end

function M.diff_blame_to_head()
    local hash, err = line_blame_commit_hash()
    if not hash then
        vim.notify("Could not get commit hash: " .. err, vim.log.levels.ERROR)
        return
    end
    vim.cmd("DiffviewFileHistory --base=" .. hash)
end


return M

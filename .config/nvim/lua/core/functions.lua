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

function M.toggle_bookmark()
    require("lspmark.bookmarks").toggle_bookmark()
end

function M.toggle_bookmark_display()
    vim.g.lspmark_signs_visible = not (vim.g.lspmark_signs_visible ~= false)
    local bookmarks = require("lspmark.bookmarks")

    if vim.g.lspmark_signs_visible then
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
                bookmarks.display_bookmarks(buf)
            end
        end
        M.notify("Bookmark signs visible", vim.log.levels.INFO)
        return
    end

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
            vim.fn.sign_unplace("lspmark", { buffer = buf })
        end
    end
    M.notify("Bookmark signs hidden", vim.log.levels.INFO)
end

function M.delete_all_bookmarks()
    vim.ui.input({ prompt = "Delete all bookmarks? (y/N): " }, function(input)
        if input ~= "y" and input ~= "Y" then
            return
        end

        local bookmarks = require("lspmark.bookmarks")
        bookmarks.bookmarks = {}
        bookmarks.save_bookmarks()

        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.fn.sign_unplace("lspmark", { buffer = buf })
            end
        end

        M.notify("All bookmarks deleted", vim.log.levels.INFO)
    end)
end

local function collect_current_file_bookmarks()
    local bookmarks = require("lspmark.bookmarks")
    local utils = require("lspmark.utils")
    local bufnr = vim.api.nvim_get_current_buf()

    if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
        bookmarks.lsp_calibrate_bookmarks(bufnr, false, bookmarks.bookmark_file)
    end

    local file_name = utils.standarize_path(vim.api.nvim_buf_get_name(bufnr))
    if file_name == "" or not bookmarks.bookmarks[file_name] then
        return {}
    end

    local locations = {}
    for kind, kind_symbols in pairs(bookmarks.bookmarks[file_name]) do
        if kind == bookmarks.plain_magic then
            local marks = kind_symbols[bookmarks.plain_magic] or kind_symbols
            for _, mark in ipairs(marks) do
                table.insert(locations, { lnum = mark.line, col = mark.col or 0 })
            end
        else
            for _, name_symbols in pairs(kind_symbols) do
                for offset, marks in pairs(name_symbols) do
                    for _, mark in ipairs(marks) do
                        table.insert(locations, {
                            lnum = mark.range[1] + tonumber(offset) + 1,
                            col = mark.col or 0,
                        })
                    end
                end
            end
        end
    end

    table.sort(locations, function(a, b)
        if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
        end
        return a.col < b.col
    end)

    return locations
end

local function goto_bookmark_in_direction(direction)
    local locations = collect_current_file_bookmarks()
    if #locations == 0 then
        M.notify("No bookmarks in this file", vim.log.levels.WARN)
        return
    end

    local cur_lnum = vim.api.nvim_win_get_cursor(0)[1]
    local min_bm = locations[1]
    local max_bm = locations[#locations]
    local target

    if direction == "next" then
        if cur_lnum >= max_bm.lnum then
            target = min_bm
        else
            for _, loc in ipairs(locations) do
                if loc.lnum > cur_lnum then
                    target = loc
                    break
                end
            end
        end
    elseif cur_lnum <= min_bm.lnum then
        target = max_bm
    else
        for i = #locations, 1, -1 do
            if locations[i].lnum < cur_lnum then
                target = locations[i]
                break
            end
        end
    end

    if target then
        vim.api.nvim_win_set_cursor(0, { target.lnum, target.col })
    end
end

function M.goto_next_bookmark()
    goto_bookmark_in_direction("next")
end

function M.goto_prev_bookmark()
    goto_bookmark_in_direction("prev")
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
    vim.cmd("DiffviewFileHistory --range=" .. hash .. "~.." .. hash .. " %")
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

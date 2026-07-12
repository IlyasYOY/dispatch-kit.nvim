local M = {}

function M.notify(message, level)
    vim.notify("dispatch-kit: " .. message, level or vim.log.levels.WARN)
end

function M.buffer_path(bufnr, modifier)
    return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), modifier)
end

function M.is_test_file(bufnr, pattern)
    local path = vim.api.nvim_buf_get_name(bufnr)
    if not path:match(pattern) then
        M.notify "not a test file"
        return false
    end
    return true
end

function M.action(opts)
    return {
        name = opts.name,
        scope = opts.scope,
        desc = opts.desc,
        command = opts.command,
        bang = opts.bang,
        count = opts.count,
        nargs = opts.nargs,
        keymaps = opts.keymaps,
    }
end

function M.repeat_last(name, keymap, lang)
    return {
        name = name,
        keymap = keymap,
        desc = "run the last command again",
        empty_message = "no previous " .. lang .. " command to run",
    }
end

return M

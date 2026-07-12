local M = {}

function M.root(path)
    local source = debug.getinfo(1, "S").source:sub(2)
    local repo = vim.fn.fnamemodify(source, ":p:h:h")
    return path and vim.fs.joinpath(repo, path) or repo
end

function M.work(path)
    local base = vim.env.DISPATCH_KIT_TEST_WORK or M.root ".test-work"
    return path and vim.fs.joinpath(base, path) or base
end

function M.reset_buffers()
    vim.cmd "silent! %bwipeout!"
    vim.cmd "enew"
end

function M.buffer(filetype, name)
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, name or M.work "sample.txt")
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = filetype
    return bufnr
end

function M.task(command)
    return {
        id = "sample.test",
        filetypes = { "sample" },
        compiler = "make",
        actions = {
            {
                name = "SampleTestAll",
                scope = "all",
                desc = "run sample tests",
                bang = true,
                count = 0,
                keymaps = {
                    run = "<localleader>ta",
                    bang = "<localleader>tA",
                },
                command = command,
            },
        },
        repeat_last = {
            name = "SampleTestLast",
            keymap = "<localleader>tl",
            desc = "repeat sample tests",
        },
    }
end

return M

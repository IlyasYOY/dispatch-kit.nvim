local M = {}

local last_by_task = {}

local function copy_spec(spec)
    return {
        argv = vim.deepcopy(spec.argv),
        cwd = spec.cwd,
        compiler = spec.compiler,
        bufnr = spec.bufnr,
    }
end

function M.set(task_id, spec)
    last_by_task[task_id] = copy_spec(spec)
end

function M.get(task_id)
    local spec = last_by_task[task_id]
    return spec and copy_spec(spec) or nil
end

function M.clear()
    last_by_task = {}
end

return M

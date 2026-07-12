local M = {}

local valid_backends = {
    auto = true,
    dispatch = true,
    makeprg = true,
}

local backend = "auto"
local makeprg = { bang = true, silent = true }

local function notify(message, level)
    vim.notify("dispatch-kit: " .. message, level or vim.log.levels.ERROR)
end

local function validate_spec(spec)
    if type(spec) ~= "table" or type(spec.argv) ~= "table" then
        return nil, "command must return a table with argv"
    end
    if #spec.argv == 0 then
        return nil, "argv must not be empty"
    end
    for index, value in ipairs(spec.argv) do
        if type(value) ~= "string" or value == "" then
            return nil, "argv[" .. index .. "] must be a non-empty string"
        end
    end
    if spec.cwd ~= nil and (type(spec.cwd) ~= "string" or spec.cwd == "") then
        return nil, "cwd must be a non-empty string"
    end
    if
        spec.compiler ~= nil
        and (
            type(spec.compiler) ~= "string"
            or not spec.compiler:match "^[%w_.-]+$"
        )
    then
        return nil, "compiler contains unsupported characters"
    end
    return {
        argv = vim.deepcopy(spec.argv),
        cwd = spec.cwd,
        compiler = spec.compiler,
        bufnr = spec.bufnr,
    }
end

function M.shell_join(argv)
    return table.concat(
        vim.tbl_map(function(value)
            return vim.fn.shellescape(value)
        end, argv),
        " "
    )
end

local function dispatch_command(spec)
    local parts = {}
    if spec.compiler then
        parts[#parts + 1] = "-compiler=" .. spec.compiler
    end
    if spec.cwd then
        parts[#parts + 1] = "-dir=" .. vim.fn.fnameescape(spec.cwd)
    end
    parts[#parts + 1] = M.shell_join(spec.argv)

    local ok, err = pcall(vim.cmd, "Dispatch " .. table.concat(parts, " "))
    if not ok then
        notify("Dispatch failed: " .. tostring(err))
        return false
    end
    return true
end

local function makeprg_command(spec)
    local command = M.shell_join(spec.argv)
    if spec.cwd then
        command = "cd " .. vim.fn.shellescape(spec.cwd) .. " && " .. command
    end
    return command
end

local function run_makeprg(spec)
    local bufnr = spec.bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then
        notify "originating buffer is no longer valid"
        return false
    end

    local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
        local saved = {
            makeprg = vim.bo.makeprg,
            errorformat = vim.bo.errorformat,
            current_compiler = vim.b.current_compiler,
        }

        local run_ok, run_err = xpcall(function()
            if spec.compiler then
                vim.cmd("compiler! " .. spec.compiler)
            end
            vim.bo.makeprg = makeprg_command(spec)
            local command = makeprg.silent and "silent make" or "make"
            if makeprg.bang then
                command = command .. "!"
            end
            vim.cmd(command)
        end, debug.traceback)

        vim.bo.makeprg = saved.makeprg
        vim.bo.errorformat = saved.errorformat
        vim.b.current_compiler = saved.current_compiler

        if not run_ok then
            error(run_err, 0)
        end
    end)

    if not ok then
        notify("makeprg fallback failed: " .. tostring(err))
        return false
    end
    return true
end

function M.setup(value, makeprg_opts)
    value = value or "auto"
    if not valid_backends[value] then
        error("dispatch-kit: invalid backend '" .. tostring(value) .. "'", 0)
    end
    backend = value
    makeprg = vim.deepcopy(makeprg_opts or { bang = true, silent = true })
end

function M.run(raw_spec)
    local spec, err = validate_spec(raw_spec)
    if not spec then
        notify(err)
        return false
    end

    local selected = backend
    if selected == "auto" then
        selected = vim.fn.exists ":Dispatch" == 2 and "dispatch" or "makeprg"
    end
    if selected == "dispatch" and vim.fn.exists ":Dispatch" ~= 2 then
        notify "backend is 'dispatch', but :Dispatch is unavailable"
        return false
    end
    if selected == "dispatch" then
        return dispatch_command(spec)
    end
    return run_makeprg(spec)
end

return M

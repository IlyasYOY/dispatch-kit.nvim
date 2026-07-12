local runner = require "dispatch-kit.runner"
local state = require "dispatch-kit.state"

local M = {}

local tasks = {}
local owned = {}
local augroup

local function notify(message, level)
    vim.notify("dispatch-kit: " .. message, level or vim.log.levels.WARN)
end

local function command_exists(bufnr, name)
    return vim.api.nvim_buf_get_commands(bufnr, { builtin = false })[name]
        ~= nil
end

local function keymap_exists(bufnr, mode, lhs)
    local canonical_lhs = vim.api.nvim_replace_termcodes(lhs, true, true, true)
    for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
        if keymap.lhs == canonical_lhs then
            return true
        end
    end
    return false
end

local function cleanup_buffer(bufnr)
    local registrations = owned[bufnr]
    if not registrations or not vim.api.nvim_buf_is_valid(bufnr) then
        owned[bufnr] = nil
        return
    end

    for _, name in ipairs(registrations.commands) do
        pcall(vim.api.nvim_buf_del_user_command, bufnr, name)
    end
    for _, keymap in ipairs(registrations.keymaps) do
        pcall(vim.keymap.del, keymap.mode, keymap.lhs, { buffer = bufnr })
    end
    owned[bufnr] = nil
end

local function validate_command_spec(task, spec, bufnr)
    if type(spec) ~= "table" then
        notify("task '" .. task.id .. "' returned an invalid command")
        return nil
    end
    spec = vim.deepcopy(spec)
    if spec.compiler == nil then
        spec.compiler = task.compiler
    end
    spec.bufnr = bufnr
    return spec
end

local function execute_result(task, bufnr, result)
    if result == nil then
        return
    end
    if type(result) == "function" then
        result(function(deferred_result)
            execute_result(task, bufnr, deferred_result)
        end)
        return
    end

    local spec = validate_command_spec(task, result, bufnr)
    if spec and runner.run(spec) then
        state.set(task.id, spec)
    end
end

local function execute_action(task, action, bufnr, command_opts)
    local ctx = {
        bufnr = bufnr,
        scope = action.scope,
        bang = command_opts.bang == true,
        count = command_opts.count or 0,
        args = command_opts.args or "",
        fargs = command_opts.fargs or {},
    }
    local ok, result = xpcall(function()
        if type(action.command) == "function" then
            return action.command(ctx)
        end
        return action.command
    end, debug.traceback)
    if not ok then
        notify(
            "task '" .. task.id .. "' command failed: " .. tostring(result),
            vim.log.levels.ERROR
        )
        return
    end
    execute_result(task, bufnr, result)
end

local function create_command(bufnr, task, action)
    if command_exists(bufnr, action.name) then
        notify(
            "buffer-local command :"
                .. action.name
                .. " already exists; preserving it"
        )
        return false
    end

    local opts = { desc = action.desc }
    if action.bang then
        opts.bang = true
    end
    if action.count ~= nil then
        opts.count = action.count
    end
    if action.nargs ~= nil then
        opts.nargs = action.nargs
    end

    vim.api.nvim_buf_create_user_command(bufnr, action.name, function(cmd_opts)
        execute_action(task, action, bufnr, cmd_opts)
    end, opts)
    owned[bufnr].commands[#owned[bufnr].commands + 1] = action.name
    return true
end

local function create_keymap(bufnr, task, action, lhs, bang)
    if not lhs then
        return
    end
    if keymap_exists(bufnr, "n", lhs) then
        notify(
            "buffer-local keymap " .. lhs .. " already exists; preserving it"
        )
        return
    end

    vim.keymap.set("n", lhs, function()
        execute_action(task, action, bufnr, {
            bang = bang,
            count = vim.v.count,
            args = "",
            fargs = {},
        })
    end, { buffer = bufnr, desc = action.desc })
    owned[bufnr].keymaps[#owned[bufnr].keymaps + 1] = {
        mode = "n",
        lhs = lhs,
    }
end

local function create_repeat(bufnr, task)
    local repeat_opts = task.repeat_last
    if not repeat_opts then
        return
    end
    if command_exists(bufnr, repeat_opts.name) then
        notify(
            "buffer-local command :"
                .. repeat_opts.name
                .. " already exists; preserving it"
        )
        return
    end

    local callback = function()
        local spec = state.get(task.id)
        if not spec then
            notify(
                repeat_opts.empty_message
                    or ("no previous " .. task.id .. " command")
            )
            return
        end
        spec.bufnr = bufnr
        runner.run(spec)
    end

    vim.api.nvim_buf_create_user_command(bufnr, repeat_opts.name, callback, {
        desc = repeat_opts.desc or "run the last command again",
    })
    owned[bufnr].commands[#owned[bufnr].commands + 1] = repeat_opts.name

    if repeat_opts.keymap then
        if keymap_exists(bufnr, "n", repeat_opts.keymap) then
            notify(
                "buffer-local keymap "
                    .. repeat_opts.keymap
                    .. " already exists; preserving it"
            )
            return
        end
        vim.keymap.set("n", repeat_opts.keymap, callback, {
            buffer = bufnr,
            desc = repeat_opts.desc or "run the last command again",
        })
        owned[bufnr].keymaps[#owned[bufnr].keymaps + 1] = {
            mode = "n",
            lhs = repeat_opts.keymap,
        }
    end
end

local function supports_filetype(task, filetype)
    return vim.tbl_contains(task.filetypes, filetype)
end

function M.register_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    cleanup_buffer(bufnr)
    owned[bufnr] = { commands = {}, keymaps = {} }
    local filetype = vim.bo[bufnr].filetype

    for _, task in ipairs(tasks) do
        if supports_filetype(task, filetype) then
            for _, action in ipairs(task.actions) do
                if create_command(bufnr, task, action) and action.keymaps then
                    create_keymap(
                        bufnr,
                        task,
                        action,
                        action.keymaps.run,
                        false
                    )
                    if action.bang then
                        create_keymap(
                            bufnr,
                            task,
                            action,
                            action.keymaps.bang,
                            true
                        )
                    end
                end
            end
            create_repeat(bufnr, task)
        end
    end
end

local function validate_action(task_id, action)
    if type(action) ~= "table" then
        error("dispatch-kit: task '" .. task_id .. "' has an invalid action", 0)
    end
    if type(action.name) ~= "string" or action.name == "" then
        error("dispatch-kit: task '" .. task_id .. "' action needs a name", 0)
    end
    if type(action.desc) ~= "string" or action.desc == "" then
        error(
            "dispatch-kit: action '" .. action.name .. "' needs a description",
            0
        )
    end
    if
        type(action.command) ~= "function"
        and type(action.command) ~= "table"
    then
        error("dispatch-kit: action '" .. action.name .. "' needs a command", 0)
    end
end

local function validate_tasks(value)
    local ids = {}
    for _, task in ipairs(value) do
        if type(task.id) ~= "string" or task.id == "" then
            error "dispatch-kit: every task needs a non-empty id"
        end
        if ids[task.id] then
            error("dispatch-kit: duplicate task id '" .. task.id .. "'", 0)
        end
        ids[task.id] = true
        if type(task.filetypes) ~= "table" or #task.filetypes == 0 then
            error("dispatch-kit: task '" .. task.id .. "' needs filetypes", 0)
        end
        if type(task.actions) ~= "table" or #task.actions == 0 then
            error("dispatch-kit: task '" .. task.id .. "' needs actions", 0)
        end
        for _, action in ipairs(task.actions) do
            validate_action(task.id, action)
        end
    end
end

function M.setup(new_tasks)
    validate_tasks(new_tasks)
    for bufnr in pairs(owned) do
        cleanup_buffer(bufnr)
    end
    state.clear()
    tasks = new_tasks

    if augroup then
        pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end
    augroup = vim.api.nvim_create_augroup("dispatch-kit", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
        group = augroup,
        callback = function(event)
            M.register_buffer(event.buf)
        end,
    })

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if
            vim.api.nvim_buf_is_loaded(bufnr)
            and vim.bo[bufnr].filetype ~= ""
        then
            M.register_buffer(bufnr)
        end
    end
end

return M

local M = {}

local adapter_names = {
    "go",
    "java",
    "python",
    "javascript",
    "proto",
    "make",
}

local known_adapters = {}
for _, name in ipairs(adapter_names) do
    known_adapters[name] = true
end

local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end

local function resolve_makeprg(value)
    if value == nil then
        return { bang = true, silent = true }
    end
    if type(value) ~= "table" then
        error "dispatch-kit: makeprg must be a table"
    end
    for name in pairs(value) do
        if name ~= "bang" and name ~= "silent" then
            error("dispatch-kit: unknown makeprg option '" .. name .. "'", 0)
        end
    end
    for _, name in ipairs { "bang", "silent" } do
        if value[name] ~= nil and type(value[name]) ~= "boolean" then
            error("dispatch-kit: makeprg." .. name .. " must be a boolean", 0)
        end
    end
    return {
        bang = value.bang == nil and true or value.bang,
        silent = value.silent == nil and true or value.silent,
    }
end

function M.resolve(opts)
    opts = opts or {}
    if type(opts) ~= "table" then
        error "dispatch-kit: setup options must be a table"
    end
    for name in pairs(opts) do
        if
            name ~= "backend"
            and name ~= "makeprg"
            and name ~= "adapters"
            and name ~= "tasks"
        then
            error("dispatch-kit: unknown setup option '" .. name .. "'", 0)
        end
    end

    local adapters = opts.adapters or {}
    local custom_tasks = opts.tasks or {}
    if type(adapters) ~= "table" then
        error "dispatch-kit: adapters must be a table"
    end
    if type(custom_tasks) ~= "table" then
        error "dispatch-kit: tasks must be a table"
    end
    for name in pairs(adapters) do
        if not known_adapters[name] then
            error("dispatch-kit: unknown adapter '" .. name .. "'", 0)
        end
    end

    local resolved = vim.deepcopy(custom_tasks)
    for _, name in ipairs(adapter_names) do
        local value = adapters[name]
        if value then
            if value == true then
                value = {}
            elseif type(value) ~= "table" then
                error(
                    "dispatch-kit: adapter '"
                        .. name
                        .. "' must be true or a table",
                    0
                )
            end
            local adapter = require("dispatch-kit.adapters." .. name)
            append(resolved, adapter.tasks(value))
        end
    end

    return {
        backend = opts.backend or "auto",
        makeprg = resolve_makeprg(opts.makeprg),
        tasks = resolved,
    }
end

return M

local M = {}

local tests = {}
local stack = {}
local hook_stack = {}
local native_assert = _G.assert

local function reset_context()
    stack = {}
    hook_stack = {
        {
            before_each = {},
            after_each = {},
        },
    }
end

reset_context()

local function collect_hooks(kind)
    local result = {}
    for _, hooks in ipairs(hook_stack) do
        vim.list_extend(result, hooks[kind])
    end
    return result
end

local function full_name(name)
    local parts = vim.deepcopy(stack)
    parts[#parts + 1] = name
    return table.concat(parts, " ")
end

function _G.describe(name, fn)
    stack[#stack + 1] = name
    hook_stack[#hook_stack + 1] = { before_each = {}, after_each = {} }
    local ok, err = xpcall(fn, debug.traceback)
    hook_stack[#hook_stack] = nil
    stack[#stack] = nil
    if not ok then
        error(err, 0)
    end
end

function _G.it(name, fn)
    tests[#tests + 1] = {
        name = full_name(name),
        fn = fn,
        before_each = collect_hooks "before_each",
        after_each = collect_hooks "after_each",
    }
end

function _G.before_each(fn)
    local hooks = hook_stack[#hook_stack]
    hooks.before_each[#hooks.before_each + 1] = fn
end

function _G.after_each(fn)
    local hooks = hook_stack[#hook_stack]
    hooks.after_each[#hooks.after_each + 1] = fn
end

local function fail(message, level)
    error(message, (level or 1) + 1)
end

local function equal(expected, actual, message)
    if expected ~= actual then
        fail(
            message
                or (
                    "expected "
                    .. vim.inspect(expected)
                    .. ", got "
                    .. vim.inspect(actual)
                ),
            2
        )
    end
end

local function not_equal(expected, actual, message)
    if expected == actual then
        fail(
            message or ("expected value not to equal " .. vim.inspect(expected)),
            2
        )
    end
end

local function same(expected, actual, message)
    if not vim.deep_equal(expected, actual) then
        fail(
            message
                or (
                    "expected "
                    .. vim.inspect(expected)
                    .. ", got "
                    .. vim.inspect(actual)
                ),
            2
        )
    end
end

local function truthy(value, message)
    if not value then
        fail(
            message or ("expected truthy value, got " .. vim.inspect(value)),
            2
        )
    end
end

local function falsy(value, message)
    if value then
        fail(message or ("expected falsy value, got " .. vim.inspect(value)), 2)
    end
end

local function is_nil(value, message)
    if value ~= nil then
        fail(message or ("expected nil, got " .. vim.inspect(value)), 2)
    end
end

local function is_not_nil(value, message)
    if value == nil then
        fail(message or "expected non-nil value", 2)
    end
end

local function has_error(fn, expected)
    local ok, err = pcall(fn)
    if ok then
        fail("expected function to error", 2)
    end
    if expected and not tostring(err):find(expected, 1, true) then
        fail(
            ("expected error containing %s, got %s"):format(
                vim.inspect(expected),
                vim.inspect(err)
            ),
            2
        )
    end
    return err
end

local assert_table = setmetatable({}, {
    __call = function(_, value, message)
        return native_assert(value, message)
    end,
})
assert_table.equal = equal
assert_table.equals = equal
assert_table.same = same
assert_table.not_equal = not_equal
assert_table.truthy = truthy
assert_table.falsy = falsy
assert_table.is_true = function(value, message)
    equal(true, value, message)
end
assert_table.is_false = function(value, message)
    equal(false, value, message)
end
assert_table.is_nil = is_nil
assert_table.is_not_nil = is_not_nil
assert_table.has_error = has_error
assert_table.True = assert_table.is_true
assert_table.False = assert_table.is_false
assert_table.Falsy = falsy
assert_table.number = function(value)
    if type(value) ~= "number" then
        fail("expected number, got " .. vim.inspect(value), 2)
    end
end
assert_table.are = assert_table
assert_table.is = assert_table
assert_table.are_not = {
    equal = not_equal,
    equals = not_equal,
    same = function(expected, actual, message)
        if vim.deep_equal(expected, actual) then
            fail(
                message
                    or ("expected value not to equal " .. vim.inspect(expected)),
                2
            )
        end
    end,
}
_G.assert = assert_table

local function default_files()
    local result = {}
    for _, pattern in ipairs { "lua/**/*_spec.lua", "tests/**/*_spec.lua" } do
        vim.list_extend(
            result,
            vim.fn.globpath(vim.fn.getcwd(), pattern, true, true)
        )
    end
    table.sort(result)
    return result
end

local function normalize_files(files)
    if files == nil then
        return default_files()
    end
    local result = {}
    for _, file in ipairs(files) do
        result[#result + 1] = vim.fn.fnamemodify(file, ":p")
    end
    table.sort(result)
    return result
end

local function load_files(files)
    local failures = {}
    for _, file in ipairs(files) do
        reset_context()
        local ok, err = xpcall(function()
            dofile(file)
        end, debug.traceback)
        if not ok then
            failures[#failures + 1] = { name = "load " .. file, err = err }
        end
    end
    return failures
end

local function run_test(test)
    local errors = {}
    local before_ok = true
    for _, fn in ipairs(test.before_each) do
        local ok, err = xpcall(fn, debug.traceback)
        if not ok then
            errors[#errors + 1] = "before_each: " .. err
            before_ok = false
            break
        end
    end
    if before_ok then
        local ok, err = xpcall(test.fn, debug.traceback)
        if not ok then
            errors[#errors + 1] = err
        end
    end
    for index = #test.after_each, 1, -1 do
        local ok, err = xpcall(test.after_each[index], debug.traceback)
        if not ok then
            errors[#errors + 1] = "after_each: " .. err
        end
    end
    return #errors == 0, table.concat(errors, "\n")
end

function M.run(opts)
    opts = opts or {}
    tests = {}
    reset_context()
    local failures = load_files(normalize_files(opts.files))
    for _, failure in ipairs(failures) do
        print("not ok - " .. failure.name)
        print(failure.err)
    end
    for _, test in ipairs(tests) do
        local ok, err = run_test(test)
        if ok then
            if opts.verbose then
                print("ok - " .. test.name)
            end
        else
            failures[#failures + 1] = { name = test.name, err = err }
            print("not ok - " .. test.name)
            print(err)
        end
    end
    print(("%d test(s) run"):format(#tests))
    if #failures > 0 then
        print(("%d test(s) failed"):format(#failures))
        vim.cmd "cquit 1"
    end
end

return M

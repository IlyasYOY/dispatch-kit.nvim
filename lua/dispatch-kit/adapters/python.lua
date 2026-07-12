local ts = require "dispatch-kit.treesitter"
local util = require "dispatch-kit.adapters.util"

local M = {}

local function pytest(path, name)
    local argv = { "pytest", path }
    if name then
        argv[2] = path .. "::" .. name
    end
    return { argv = argv }
end

function M.tasks()
    return {
        {
            id = "python.test",
            filetypes = { "python" },
            compiler = "pytest",
            actions = {
                util.action {
                    name = "PythonTestAll",
                    scope = "all",
                    desc = "run test for all packages",
                    keymaps = { run = "<localleader>ta" },
                    command = { argv = { "pytest" } },
                },
                util.action {
                    name = "PythonTestPackage",
                    scope = "package",
                    desc = "run test for a package",
                    keymaps = { run = "<localleader>tp" },
                    command = function(ctx)
                        return pytest(util.buffer_path(ctx.bufnr, ":p:h"))
                    end,
                },
                util.action {
                    name = "PythonTestFile",
                    scope = "file",
                    desc = "run test for a file",
                    keymaps = { run = "<localleader>tf" },
                    command = function(ctx)
                        return pytest(util.buffer_path(ctx.bufnr, ":p"))
                    end,
                },
                util.action {
                    name = "PythonTestFunction",
                    scope = "current",
                    desc = "run test for a function",
                    keymaps = { run = "<localleader>tt" },
                    command = function(ctx)
                        if not util.is_test_file(ctx.bufnr, "test_.*%.py$") then
                            return nil
                        end
                        local name = ts.enclosing_name(
                            ctx.bufnr,
                            "python",
                            "function_definition"
                        )
                        if not name then
                            util.notify "test function was not found"
                            return nil
                        end
                        return pytest(util.buffer_path(ctx.bufnr, ":p"), name)
                    end,
                },
            },
            repeat_last = util.repeat_last(
                "PythonTestLast",
                "<localleader>tl",
                "Python test"
            ),
        },
    }
end

return M

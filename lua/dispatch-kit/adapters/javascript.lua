local ts = require "dispatch-kit.treesitter"
local util = require "dispatch-kit.adapters.util"

local M = {}

local dependency_fields = {
    "dependencies",
    "devDependencies",
    "peerDependencies",
    "optionalDependencies",
}

local function package_json(bufnr)
    local path = vim.fs.find("package.json", {
        upward = true,
        path = util.buffer_path(bufnr, ":p:h"),
        type = "file",
        limit = 1,
    })[1]
    if not path then
        return nil
    end
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        return nil
    end
    local decoded_ok, decoded =
        pcall(vim.json.decode, table.concat(lines, "\n"))
    return decoded_ok and type(decoded) == "table" and decoded or nil
end

local function mentions_runner(package, runner)
    for _, field in ipairs(dependency_fields) do
        if type(package[field]) == "table" and package[field][runner] then
            return true
        end
    end
    if type(package.scripts) == "table" then
        for _, script in pairs(package.scripts) do
            if type(script) == "string" and script:find(runner, 1, true) then
                return true
            end
        end
    end
    return false
end

local function runner(bufnr)
    local package = package_json(bufnr)
    if package and mentions_runner(package, "vitest") then
        return "vitest"
    end
    return "jest"
end

local function command(ctx, scope, value)
    local selected = runner(ctx.bufnr)
    local argv = { "npx" }
    local compiler
    if selected == "vitest" then
        vim.list_extend(argv, { "vitest", "run" })
    else
        argv[#argv + 1] = "jest"
        compiler = "jest"
    end

    if scope == "all" then
        argv[#argv + 1] = "."
    elseif scope == "current" then
        vim.list_extend(argv, { "-t", value })
    else
        argv[#argv + 1] = value
    end
    return { argv = argv, compiler = compiler }
end

local function current_test_name(bufnr)
    local language = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
        or vim.bo[bufnr].filetype
    if not ts.parser(bufnr, language) then
        return nil
    end
    return ts.find_enclosing(bufnr, function(node)
        if node:type() ~= "call_expression" then
            return nil
        end
        local function_node = node:field("function")[1]
        if not function_node then
            return nil
        end
        local function_name = vim.treesitter.get_node_text(function_node, bufnr)
        if function_name ~= "test" and function_name ~= "it" then
            return nil
        end
        local arguments = node:field("arguments")[1]
        local name_node = arguments and arguments:named_child(0) or nil
        if not name_node or name_node:type() ~= "string" then
            return nil
        end
        return vim.treesitter
            .get_node_text(name_node, bufnr)
            :gsub("^[\"']", "")
            :gsub("[\"']$", "")
    end)
end

function M.tasks()
    return {
        {
            id = "javascript.test",
            filetypes = {
                "javascript",
                "javascriptreact",
                "typescript",
                "typescriptreact",
            },
            actions = {
                util.action {
                    name = "JSTestAll",
                    scope = "all",
                    desc = "run test for all packages",
                    keymaps = { run = "<localleader>ta" },
                    command = function(ctx)
                        return command(ctx, "all")
                    end,
                },
                util.action {
                    name = "JSTestPackage",
                    scope = "package",
                    desc = "run test for a package",
                    keymaps = { run = "<localleader>tp" },
                    command = function(ctx)
                        return command(
                            ctx,
                            "package",
                            util.buffer_path(ctx.bufnr, ":p:h")
                        )
                    end,
                },
                util.action {
                    name = "JSTestFile",
                    scope = "file",
                    desc = "run test for a file",
                    keymaps = { run = "<localleader>tf" },
                    command = function(ctx)
                        return command(
                            ctx,
                            "file",
                            util.buffer_path(ctx.bufnr, ":p")
                        )
                    end,
                },
                util.action {
                    name = "JSTestFunction",
                    scope = "current",
                    desc = "run test for a function",
                    keymaps = { run = "<localleader>tt" },
                    command = function(ctx)
                        if
                            not util.is_test_file(ctx.bufnr, "%.test%.[jt]sx?$")
                        then
                            return nil
                        end
                        local name = current_test_name(ctx.bufnr)
                        if not name then
                            util.notify "test function was not found"
                            return nil
                        end
                        return command(ctx, "current", name)
                    end,
                },
            },
            repeat_last = util.repeat_last(
                "JSTestLast",
                "<localleader>tl",
                "JavaScript/TypeScript test"
            ),
        },
    }
end

return M

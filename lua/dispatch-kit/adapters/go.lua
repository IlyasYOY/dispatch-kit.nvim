local ts = require "dispatch-kit.treesitter"
local util = require "dispatch-kit.adapters.util"

local M = {}

local function build_tags(bufnr)
    local tags = {}
    for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        local expression = line:match "^%s*//go:build%s+(.+)$"
        if expression then
            tags[#tags + 1] = expression
        end
    end
    return tags
end

local function add_tags(argv, bufnr, verbose)
    local tags = build_tags(bufnr)
    if #tags == 0 then
        return
    end
    if verbose then
        argv[#argv + 1] = "-v"
    end
    argv[#argv + 1] = "-tags"
    argv[#argv + 1] = table.concat(tags, " ")
end

local golangci_config_names = {
    ".golangci.pipeline.yaml",
    ".golangci.pipeline.yml",
    ".golangci.yml",
    ".golangci.yaml",
}

local function golangci_binary(bufnr, opts)
    if opts.binary then
        return vim.fn.expand(opts.binary)
    end
    local start = util.buffer_path(bufnr, ":p:h")
    local project_binary = vim.fs.find("bin/golangci-lint", {
        upward = true,
        path = start,
        type = "file",
        limit = 1,
    })[1]
    if project_binary and vim.fn.executable(project_binary) == 1 then
        return project_binary
    end
    return "golangci-lint"
end

local function golangci_config(bufnr, opts)
    local start = util.buffer_path(bufnr, ":p:h")
    local project_config = vim.fs.find(golangci_config_names, {
        upward = true,
        path = start,
        type = "file",
        limit = 1,
    })[1]
    if project_config then
        return project_config
    end
    if opts.fallback_config then
        return vim.fn.expand(opts.fallback_config)
    end
end

local function golangci_version(binary)
    local result = vim.system({ binary, "version" }, { text = true }):wait()
    return result.stdout or ""
end

local function golangci_command(bufnr, opts, path)
    local binary = golangci_binary(bufnr, opts)
    local version = golangci_version(binary)
    local argv = { binary, "run", "--fix=false" }
    if version:match "version v2%.0%." or version:match "version 2%.0%." then
        vim.list_extend(argv, {
            "--show-stats=false",
            "--output.tab.path=stdout",
        })
    elseif version:match "version v2" or version:match "version 2" then
        vim.list_extend(argv, {
            "--show-stats=false",
            "--output.tab.path=stdout",
            "--path-mode=abs",
        })
    else
        argv[#argv + 1] = "--out-format=tab"
    end

    local config = golangci_config(bufnr, opts)
    if config and vim.fn.filereadable(config) == 1 then
        argv[#argv + 1] = "--config"
        argv[#argv + 1] = config
    end
    argv[#argv + 1] = path
    return { argv = argv }
end

local function lint_task(opts)
    return {
        id = "go.lint",
        filetypes = { "go" },
        compiler = "make",
        actions = {
            util.action {
                name = "GoLangCiLintAll",
                scope = "all",
                desc = "lint all packages",
                keymaps = { run = "<localleader>la" },
                command = function(ctx)
                    return golangci_command(ctx.bufnr, opts, "./...")
                end,
            },
            util.action {
                name = "GoLangCiLintPackage",
                scope = "package",
                desc = "lint current package",
                keymaps = { run = "<localleader>lp" },
                command = function(ctx)
                    return golangci_command(
                        ctx.bufnr,
                        opts,
                        util.buffer_path(ctx.bufnr, ":p:h")
                    )
                end,
            },
            util.action {
                name = "GoLangCiLintFile",
                scope = "file",
                desc = "lint current file",
                keymaps = { run = "<localleader>lf" },
                command = function(ctx)
                    return golangci_command(
                        ctx.bufnr,
                        opts,
                        util.buffer_path(ctx.bufnr, ":p")
                    )
                end,
            },
        },
        repeat_last = util.repeat_last(
            "GoLangCiLintLast",
            "<localleader>ll",
            "Go lint"
        ),
    }
end

local function go_test_command(ctx, path, name)
    local argv = { "go", "test", "-fullpath" }
    add_tags(argv, ctx.bufnr, true)
    if ctx.bang then
        argv[#argv + 1] = "-short"
    end
    if ctx.count ~= 0 then
        argv[#argv + 1] = "-count=" .. ctx.count
        argv[#argv + 1] = "-shuffle=on"
    end
    if name then
        argv[#argv + 1] = "-run"
        argv[#argv + 1] = name
    end
    argv[#argv + 1] = path
    return { argv = argv }
end

local function test_action(name, scope, desc, key, command)
    return util.action {
        name = name,
        scope = scope,
        desc = desc,
        command = command,
        bang = true,
        count = 0,
        keymaps = {
            run = "<localleader>t" .. key,
            bang = "<localleader>t" .. key:upper(),
        },
    }
end

local function test_task()
    return {
        id = "go.test",
        filetypes = { "go" },
        compiler = "make",
        actions = {
            test_action(
                "GoTestAll",
                "all",
                "run test for all packages",
                "a",
                function(ctx)
                    return go_test_command(ctx, "./...")
                end
            ),
            test_action(
                "GoTestPackage",
                "package",
                "run test for a package",
                "p",
                function(ctx)
                    return go_test_command(
                        ctx,
                        util.buffer_path(ctx.bufnr, ":p:h")
                    )
                end
            ),
            test_action(
                "GoTestFile",
                "file",
                "run test for a file",
                "f",
                function(ctx)
                    return go_test_command(
                        ctx,
                        util.buffer_path(ctx.bufnr, ":p")
                    )
                end
            ),
            test_action(
                "GoTestFunction",
                "current",
                "run test for a function",
                "t",
                function(ctx)
                    if not util.is_test_file(ctx.bufnr, "_test%.go$") then
                        return nil
                    end
                    local name = ts.enclosing_name(
                        ctx.bufnr,
                        "go",
                        "function_declaration"
                    )
                    if not name or not name:match "^Test.+" then
                        util.notify "test function was not found"
                        return nil
                    end
                    return go_test_command(
                        ctx,
                        util.buffer_path(ctx.bufnr, ":p:h"),
                        name
                    )
                end
            ),
        },
        repeat_last = util.repeat_last(
            "GoTestLast",
            "<localleader>tl",
            "Go test"
        ),
    }
end

local function go_bench_command(ctx, path, name)
    local argv = { "go", "test", "-fullpath", "-bench=" .. name }
    add_tags(argv, ctx.bufnr, false)
    if ctx.bang then
        argv[#argv + 1] = "-run=^$"
    end
    if ctx.count ~= 0 then
        argv[#argv + 1] = "-count=" .. ctx.count
    end
    argv[#argv + 1] = path
    return { argv = argv }
end

local function bench_action(name, scope, desc, key, command)
    return util.action {
        name = name,
        scope = scope,
        desc = desc,
        command = command,
        bang = true,
        count = 0,
        keymaps = {
            run = "<localleader>m" .. key,
            bang = "<localleader>m" .. key:upper(),
        },
    }
end

local function benchmark_task()
    return {
        id = "go.benchmark",
        filetypes = { "go" },
        compiler = "make",
        actions = {
            bench_action(
                "GoBenchTestAll",
                "all",
                "run all benchmarks",
                "a",
                function(ctx)
                    return go_bench_command(ctx, "./...", ".")
                end
            ),
            bench_action(
                "GoBenchTestPackage",
                "package",
                "run package benchmarks",
                "p",
                function(ctx)
                    return go_bench_command(
                        ctx,
                        util.buffer_path(ctx.bufnr, ":p:h"),
                        "."
                    )
                end
            ),
            bench_action(
                "GoBenchTestFile",
                "file",
                "run file benchmarks",
                "f",
                function(ctx)
                    return go_bench_command(
                        ctx,
                        util.buffer_path(ctx.bufnr, ":p"),
                        "."
                    )
                end
            ),
            bench_action(
                "GoBenchTestFunction",
                "current",
                "run benchmark under cursor",
                "b",
                function(ctx)
                    local name = ts.enclosing_name(
                        ctx.bufnr,
                        "go",
                        "function_declaration"
                    )
                    if not name or not name:match "^Benchmark" then
                        util.notify "benchmark function was not found"
                        return nil
                    end
                    return go_bench_command(
                        ctx,
                        util.buffer_path(ctx.bufnr, ":p:h"),
                        "^" .. name .. "$"
                    )
                end
            ),
        },
        repeat_last = util.repeat_last(
            "GoBenchTestLast",
            "<localleader>ml",
            "Go benchmark"
        ),
    }
end

local function build_command(ctx, path)
    local argv = { "go", "build" }
    add_tags(argv, ctx.bufnr, false)
    argv[#argv + 1] = path
    return { argv = argv }
end

local function build_task()
    return {
        id = "go.build",
        filetypes = { "go" },
        compiler = "make",
        actions = {
            util.action {
                name = "GoBuildAll",
                scope = "all",
                desc = "build all packages",
                keymaps = { run = "<localleader>ba" },
                command = function(ctx)
                    return build_command(ctx, "./...")
                end,
            },
            util.action {
                name = "GoBuildPackage",
                scope = "package",
                desc = "build current package",
                keymaps = { run = "<localleader>bp" },
                command = function(ctx)
                    return build_command(ctx, ".")
                end,
            },
            util.action {
                name = "GoBuildFile",
                scope = "file",
                desc = "build current file",
                keymaps = { run = "<localleader>bf" },
                command = function(ctx)
                    return build_command(ctx, util.buffer_path(ctx.bufnr, ":p"))
                end,
            },
        },
        repeat_last = util.repeat_last(
            "GoBuildLast",
            "<localleader>bl",
            "Go build"
        ),
    }
end

function M.tasks(opts)
    local lint_opts = opts.golangci
    if lint_opts == nil or lint_opts == true then
        lint_opts = {}
    elseif lint_opts == false then
        lint_opts = nil
    end

    local result = {}
    if lint_opts then
        result[#result + 1] = lint_task(lint_opts)
    end
    result[#result + 1] = benchmark_task()
    result[#result + 1] = test_task()
    result[#result + 1] = build_task()
    return result
end

return M

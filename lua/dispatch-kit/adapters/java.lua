local ts = require "dispatch-kit.treesitter"
local util = require "dispatch-kit.adapters.util"

local M = {}

local gradle_markers = {
    "gradlew",
    "settings.gradle",
    "settings.gradle.kts",
    "build.gradle",
    "build.gradle.kts",
}

local maven_markers = { "mvnw", "pom.xml" }

local function test_runner(bufnr)
    local root = vim.fs.root(bufnr, gradle_markers)
    if root then
        return {
            name = "gradle",
            root = root,
            executable = vim.fn.filereadable(vim.fs.joinpath(root, "gradlew"))
                        == 1
                    and "./gradlew"
                or "gradle",
        }
    end

    root = vim.fs.root(bufnr, maven_markers)
    if root then
        return {
            name = "maven",
            root = root,
            executable = vim.fn.filereadable(vim.fs.joinpath(root, "mvnw"))
                        == 1
                    and "./mvnw"
                or "mvn",
        }
    end

    util.notify "no Gradle or Maven project root found for Java tests"
end

local function test_command(bufnr, class_name, method_name)
    local runner = test_runner(bufnr)
    if not runner then
        return nil
    end

    local argv
    if runner.name == "gradle" then
        argv = { runner.executable, "test", "--console=plain" }
        if class_name then
            local filter = class_name
            if method_name then
                filter = filter .. "." .. method_name
            end
            vim.list_extend(argv, { "--tests", filter })
        end
    else
        argv = { runner.executable }
        if class_name then
            local filter = class_name
            if method_name then
                filter = filter .. "#" .. method_name
            end
            argv[#argv + 1] = "-Dtest=" .. filter
        end
        argv[#argv + 1] = "test"
    end

    return { argv = argv, cwd = runner.root }
end

local function lint_task(opts)
    local pmd = opts.pmd
    if pmd == true then
        pmd = {}
    end
    local checkstyle = opts.checkstyle
    if checkstyle == true then
        checkstyle = {}
    end

    return {
        id = "java.lint",
        filetypes = { "java" },
        actions = {
            util.action {
                name = "JavaPMD",
                scope = "file",
                desc = "run PMD for current buffer",
                command = function(ctx)
                    local config = pmd and pmd.config
                    if not config or vim.fn.filereadable(config) ~= 1 then
                        util.notify "Java PMD config is not readable"
                        return nil
                    end
                    return {
                        argv = {
                            (pmd and pmd.binary) or "pmd",
                            "check",
                            "--no-cache",
                            "--dir",
                            util.buffer_path(ctx.bufnr, ":p"),
                            "-R",
                            config,
                        },
                        compiler = "make",
                    }
                end,
            },
            util.action {
                name = "JavaCheckstyle",
                scope = "file",
                desc = "run Checkstyle for current buffer",
                command = function(ctx)
                    local config = checkstyle and checkstyle.config
                    if not config or vim.fn.filereadable(config) ~= 1 then
                        util.notify "Java Checkstyle config is not readable"
                        return nil
                    end
                    return {
                        argv = {
                            (checkstyle and checkstyle.binary) or "checkstyle",
                            util.buffer_path(ctx.bufnr, ":p"),
                            "-c",
                            config,
                        },
                    }
                end,
            },
        },
        repeat_last = util.repeat_last(
            "JavaLintLast",
            "<localleader>ll",
            "Java lint"
        ),
    }
end

local function test_task()
    return {
        id = "java.test",
        filetypes = { "java" },
        actions = {
            util.action {
                name = "JavaTestAll",
                scope = "all",
                desc = "run test for all packages",
                keymaps = { run = "<localleader>ta" },
                command = function(ctx)
                    return test_command(ctx.bufnr)
                end,
            },
            util.action {
                name = "JavaTestFile",
                scope = "file",
                desc = "run test for a file",
                keymaps = { run = "<localleader>tf" },
                command = function(ctx)
                    return test_command(
                        ctx.bufnr,
                        util.buffer_path(ctx.bufnr, ":t:r")
                    )
                end,
            },
            util.action {
                name = "JavaTestFunction",
                scope = "current",
                desc = "run test for a function",
                keymaps = { run = "<localleader>tt" },
                command = function(ctx)
                    if not util.is_test_file(ctx.bufnr, "Tests?%.java$") then
                        return nil
                    end
                    local name = ts.enclosing_name(
                        ctx.bufnr,
                        "java",
                        "method_declaration"
                    )
                    if not name then
                        util.notify "test function was not found"
                        return nil
                    end
                    return test_command(
                        ctx.bufnr,
                        util.buffer_path(ctx.bufnr, ":t:r"),
                        name
                    )
                end,
            },
        },
        repeat_last = util.repeat_last(
            "JavaTestLast",
            "<localleader>tl",
            "Java test"
        ),
    }
end

function M.tasks(opts)
    return { lint_task(opts), test_task() }
end

return M

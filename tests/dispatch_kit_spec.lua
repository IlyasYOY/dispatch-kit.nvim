local dispatch_kit = require "dispatch-kit"

local function eq(expected, actual, message)
    if not vim.deep_equal(expected, actual) then
        error(
            (message or "values differ")
                .. "\nexpected: "
                .. vim.inspect(expected)
                .. "\nactual: "
                .. vim.inspect(actual),
            0
        )
    end
end

local function truthy(value, message)
    if not value then
        error(message or "expected a truthy value", 0)
    end
end

local function errors_with(fragment, callback)
    local ok, err = pcall(callback)
    eq(false, ok, "expected callback to fail")
    truthy(
        tostring(err):find(fragment, 1, true),
        "expected error to contain: " .. fragment
    )
end

local function buffer(filetype, name)
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, name or (vim.fn.getcwd() .. "/sample.txt"))
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = filetype
    return bufnr
end

local function custom_task(builder)
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
                command = builder,
            },
        },
        repeat_last = {
            name = "SampleTestLast",
            keymap = "<localleader>tl",
            desc = "repeat sample tests",
        },
    }
end

local tests = {}

tests[#tests + 1] = {
    name = "validates makeprg setup options",
    run = function()
        errors_with("makeprg must be a table", function()
            dispatch_kit.setup { makeprg = false }
        end)
        errors_with("unknown makeprg option 'other'", function()
            dispatch_kit.setup { makeprg = { other = true } }
        end)
        errors_with("makeprg.bang must be a boolean", function()
            dispatch_kit.setup { makeprg = { bang = "yes" } }
        end)
        errors_with("makeprg.silent must be a boolean", function()
            dispatch_kit.setup { makeprg = { silent = 1 } }
        end)
    end,
}

tests[#tests + 1] = {
    name = "builds every configured make command form",
    run = function()
        local runner = require "dispatch-kit.runner"
        local bufnr = buffer("text", vim.fn.getcwd() .. "/make-command.txt")

        local function capture(options)
            dispatch_kit.setup {
                backend = "makeprg",
                makeprg = options,
            }
            local original_cmd = vim.cmd
            local command
            vim.cmd = function(value)
                command = value
            end
            local ok, err = xpcall(function()
                truthy(runner.run { argv = { "true" }, bufnr = bufnr })
            end, debug.traceback)
            vim.cmd = original_cmd
            if not ok then
                error(err, 0)
            end
            return command
        end

        eq("silent make!", capture(nil))
        eq("make", capture { bang = false, silent = false })
        eq("make!", capture { bang = true, silent = false })
        eq("silent make", capture { bang = false, silent = true })
        eq("silent make!", capture { bang = true, silent = true })
    end,
}

tests[#tests + 1] = {
    name = "registers commands and keymaps only in matching buffers",
    run = function()
        dispatch_kit.setup {
            backend = "dispatch",
            tasks = { custom_task { argv = { "true" } } },
        }
        local sample = buffer("sample", vim.fn.getcwd() .. "/sample.one")
        local other = buffer("text", vim.fn.getcwd() .. "/sample.two")
        truthy(
            vim.api.nvim_buf_get_commands(sample, { builtin = false }).SampleTestAll
        )
        eq(
            nil,
            vim.api.nvim_buf_get_commands(other, { builtin = false }).SampleTestAll
        )
        eq(nil, vim.api.nvim_get_commands({ builtin = false }).SampleTestAll)
        truthy(vim.tbl_contains(
            vim.tbl_map(function(map)
                return map.lhs
            end, vim.api.nvim_buf_get_keymap(sample, "n")),
            ",ta"
        ))
    end,
}

tests[#tests + 1] = {
    name = "passes bang and count and repeats the resolved compiler",
    run = function()
        local received = {}
        pcall(vim.api.nvim_del_user_command, "Dispatch")
        vim.api.nvim_create_user_command("Dispatch", function(opts)
            received[#received + 1] = opts.args
        end, { nargs = "*" })

        local selected_compiler = "pytest"
        local context
        dispatch_kit.setup {
            backend = "dispatch",
            tasks = {
                custom_task(function(ctx)
                    context = ctx
                    return {
                        argv = { "printf", "%s", "a b;$HOME" },
                        compiler = selected_compiler,
                    }
                end),
            },
        }
        buffer("sample", vim.fn.getcwd() .. "/repeat.sample")
        vim.cmd "3SampleTestAll!"
        eq(true, context.bang)
        eq(3, context.count)
        truthy(received[1]:find("-compiler=pytest", 1, true))
        truthy(received[1]:find("'a b;$HOME'", 1, true))

        selected_compiler = "make"
        vim.cmd "SampleTestLast"
        truthy(received[2]:find("-compiler=pytest", 1, true))
        eq(nil, received[2]:find("-compiler=make", 1, true))
    end,
}

tests[#tests + 1] = {
    name = "preserves foreign buffer-local commands and mappings",
    run = function()
        dispatch_kit.setup {
            backend = "makeprg",
            tasks = { custom_task { argv = { "true" } } },
        }
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_create_user_command(
            bufnr,
            "SampleTestAll",
            function() end,
            {}
        )
        vim.keymap.set("n", "<localleader>ta", "<cmd>echo 'foreign'<cr>", {
            buffer = bufnr,
            desc = "foreign",
        })
        vim.bo[bufnr].filetype = "sample"
        eq("foreign", vim.fn.maparg(",ta", "n", false, true).desc)
        truthy(
            vim.api.nvim_buf_get_commands(bufnr, { builtin = false }).SampleTestAll
        )
    end,
}

tests[#tests + 1] = {
    name = "preserves a foreign mapping when the command name is free",
    run = function()
        dispatch_kit.setup {
            backend = "makeprg",
            tasks = { custom_task { argv = { "true" } } },
        }
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(bufnr)
        vim.keymap.set("n", "<localleader>ta", "<cmd>echo 'foreign'<cr>", {
            buffer = bufnr,
            desc = "foreign mapping only",
        })
        vim.bo[bufnr].filetype = "sample"
        eq("foreign mapping only", vim.fn.maparg(",ta", "n", false, true).desc)
        truthy(
            vim.api.nvim_buf_get_commands(bufnr, { builtin = false }).SampleTestAll
        )
    end,
}

tests[#tests + 1] = {
    name = "makeprg fallback restores local compiler options",
    run = function()
        dispatch_kit.setup {
            backend = "makeprg",
            tasks = { custom_task { argv = { "printf", "ok" } } },
        }
        local bufnr = buffer("sample", vim.fn.getcwd() .. "/fallback.sample")
        vim.bo[bufnr].makeprg = "original-command"
        vim.bo[bufnr].errorformat = "%f:%l:%m"
        local saved_compiler = vim.b[bufnr].current_compiler
        vim.cmd "SampleTestAll"
        eq("original-command", vim.bo[bufnr].makeprg)
        eq("%f:%l:%m", vim.bo[bufnr].errorformat)
        eq(saved_compiler, vim.b[bufnr].current_compiler)
    end,
}

tests[#tests + 1] = {
    name = "loads every bundled adapter without dotfiles or vim-dispatch",
    run = function()
        pcall(vim.api.nvim_del_user_command, "Dispatch")
        dispatch_kit.setup {
            adapters = {
                go = true,
                java = true,
                python = true,
                javascript = true,
                proto = true,
                make = true,
            },
        }
        local cases = {
            go = { "GoLangCiLintLast", "GoTestLast", "GoBuildLast" },
            java = { "JavaPMD", "JavaTestLast" },
            python = { "PythonTestAll", "PythonTestLast" },
            typescript = { "JSTestAll", "JSTestLast" },
            proto = { "ProtoLint", "ProtoLintBuf", "ProtoLintLast" },
            make = { "MakeTargets", "MakeTarget" },
        }
        for filetype, names in pairs(cases) do
            local bufnr =
                buffer(filetype, vim.fn.getcwd() .. "/adapter-" .. filetype)
            local commands = vim.api.nvim_buf_get_commands(bufnr, {
                builtin = false,
            })
            for _, name in ipairs(names) do
                truthy(
                    commands[name],
                    filetype .. " did not register :" .. name
                )
            end
        end
        eq(nil, vim.env.ILYASYOY_DOTFILES_DIR)
    end,
}

tests[#tests + 1] = {
    name = "JSTestLast preserves the originally detected compiler",
    run = function()
        local received = {}
        pcall(vim.api.nvim_del_user_command, "Dispatch")
        vim.api.nvim_create_user_command("Dispatch", function(opts)
            received[#received + 1] = opts.args
        end, { nargs = "*" })

        local root =
            vim.fs.joinpath(vim.fn.getcwd(), ".test-work", "javascript")
        vim.fn.mkdir(root, "p")
        local package_path = vim.fs.joinpath(root, "package.json")
        vim.fn.writefile(
            { [[{"devDependencies":{"jest":"latest"}}]] },
            package_path
        )

        dispatch_kit.setup {
            backend = "dispatch",
            adapters = { javascript = true },
        }
        buffer("typescript", vim.fs.joinpath(root, "example.test.ts"))
        vim.cmd "JSTestAll"
        truthy(received[1]:find("-compiler=jest", 1, true))

        vim.fn.writefile(
            { [[{"devDependencies":{"vitest":"latest"}}]] },
            package_path
        )
        vim.cmd "JSTestLast"
        truthy(received[2]:find("-compiler=jest", 1, true))
        eq(nil, received[2]:find("vitest", 1, true))
    end,
}

tests[#tests + 1] = {
    name = "JavaLintLast preserves the PMD compiler",
    run = function()
        local received = {}
        pcall(vim.api.nvim_del_user_command, "Dispatch")
        vim.api.nvim_create_user_command("Dispatch", function(opts)
            received[#received + 1] = opts.args
        end, { nargs = "*" })

        local root = vim.fs.joinpath(vim.fn.getcwd(), ".test-work", "java")
        vim.fn.mkdir(root, "p")
        local config = vim.fs.joinpath(root, "rules.xml")
        vim.fn.writefile({ "<ruleset/>" }, config)
        dispatch_kit.setup {
            backend = "dispatch",
            adapters = {
                java = {
                    pmd = { config = config },
                    checkstyle = { config = config },
                },
            },
        }
        buffer("java", vim.fs.joinpath(root, "ExampleTest.java"))
        vim.cmd "JavaPMD"
        truthy(received[1]:find("-compiler=make", 1, true))
        vim.cmd "JavaLintLast"
        truthy(received[2]:find("-compiler=make", 1, true))
    end,
}

return tests

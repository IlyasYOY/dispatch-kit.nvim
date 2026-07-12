local dispatch_kit = require "dispatch-kit"
local h = require "tests.helpers"

describe("dispatch-kit bundled adapters", function()
    after_each(function()
        dispatch_kit.setup {}
        pcall(vim.api.nvim_del_user_command, "Dispatch")
        h.reset_buffers()
    end)

    it("loads every adapter without dotfiles or vim-dispatch", function()
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
            local bufnr = h.buffer(filetype, h.work("adapter-" .. filetype))
            local commands = vim.api.nvim_buf_get_commands(bufnr, {
                builtin = false,
            })
            for _, name in ipairs(names) do
                assert.is_not_nil(
                    commands[name],
                    filetype .. " did not register :" .. name
                )
            end
        end
        assert.is_nil(vim.env.ILYASYOY_DOTFILES_DIR)
    end)

    it("repeats the originally detected JavaScript compiler", function()
        local received = {}
        vim.api.nvim_create_user_command("Dispatch", function(opts)
            received[#received + 1] = opts.args
        end, { nargs = "*" })

        local root = h.work "javascript"
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
        h.buffer("typescript", vim.fs.joinpath(root, "example.test.ts"))
        vim.cmd "JSTestAll"
        assert.truthy(received[1]:find("-compiler=jest", 1, true))

        vim.fn.writefile(
            { [[{"devDependencies":{"vitest":"latest"}}]] },
            package_path
        )
        vim.cmd "JSTestLast"
        assert.truthy(received[2]:find("-compiler=jest", 1, true))
        assert.is_nil(received[2]:find("vitest", 1, true))
    end)

    it("repeats the resolved Java lint compiler", function()
        local received = {}
        vim.api.nvim_create_user_command("Dispatch", function(opts)
            received[#received + 1] = opts.args
        end, { nargs = "*" })

        local root = h.work "java"
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
        h.buffer("java", vim.fs.joinpath(root, "ExampleTest.java"))
        vim.cmd "JavaPMD"
        assert.truthy(received[1]:find("-compiler=make", 1, true))
        vim.cmd "JavaLintLast"
        assert.truthy(received[2]:find("-compiler=make", 1, true))
    end)
end)

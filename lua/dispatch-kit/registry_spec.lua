local dispatch_kit = require "dispatch-kit"
local h = require "tests.helpers"

describe("dispatch-kit registry", function()
    local original_notify

    before_each(function()
        original_notify = vim.notify
        h.reset_buffers()
    end)

    after_each(function()
        vim.notify = original_notify
        dispatch_kit.setup {}
        pcall(vim.api.nvim_del_user_command, "Dispatch")
        h.reset_buffers()
    end)

    it("registers commands and keymaps only in matching buffers", function()
        dispatch_kit.setup {
            backend = "makeprg",
            tasks = { h.task { argv = { "true" } } },
        }
        local sample = h.buffer("sample", h.work "sample.one")
        local other = h.buffer("text", h.work "sample.two")
        assert.is_not_nil(vim.api.nvim_buf_get_commands(sample, {
            builtin = false,
        }).SampleTestAll)
        assert.is_nil(vim.api.nvim_buf_get_commands(other, {
            builtin = false,
        }).SampleTestAll)
        assert.is_nil(
            vim.api.nvim_get_commands({ builtin = false }).SampleTestAll
        )
        local mappings = vim.api.nvim_buf_get_keymap(sample, "n")
        assert.truthy(vim.tbl_contains(
            vim.tbl_map(function(mapping)
                return mapping.lhs
            end, mappings),
            ",ta"
        ))
    end)

    it("passes command context and repeats the resolved result", function()
        local received = {}
        local context
        vim.api.nvim_create_user_command("Dispatch", function(opts)
            received[#received + 1] = opts.args
        end, { nargs = "*" })
        dispatch_kit.setup {
            backend = "dispatch",
            tasks = {
                h.task(function(ctx)
                    context = ctx
                    return {
                        argv = { "printf", "%s", "a b;$HOME" },
                        compiler = "pytest",
                    }
                end),
            },
        }
        h.buffer("sample", h.work "repeat.sample")
        vim.cmd "3SampleTestAll!"
        assert.is_true(context.bang)
        assert.equal(3, context.count)
        assert.truthy(received[1]:find("-compiler=pytest", 1, true))

        vim.cmd "SampleTestLast"
        assert.truthy(received[2]:find("-compiler=pytest", 1, true))
    end)

    it("supports deferred command builders", function()
        local received
        vim.api.nvim_create_user_command("Dispatch", function(opts)
            received = opts.args
        end, { nargs = "*" })
        dispatch_kit.setup {
            backend = "dispatch",
            tasks = {
                h.task(function()
                    return function(done)
                        done { argv = { "true", "deferred" } }
                    end
                end),
            },
        }
        h.buffer("sample", h.work "deferred.sample")
        vim.cmd "SampleTestAll"
        assert.truthy(received:find("'deferred'", 1, true))
    end)

    it("preserves foreign commands and mappings", function()
        dispatch_kit.setup {
            backend = "makeprg",
            tasks = { h.task { argv = { "true" } } },
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
        assert.equal("foreign", vim.fn.maparg(",ta", "n", false, true).desc)
        assert.is_not_nil(vim.api.nvim_buf_get_commands(bufnr, {
            builtin = false,
        }).SampleTestAll)
    end)

    it("preserves a foreign mapping when the command name is free", function()
        dispatch_kit.setup {
            backend = "makeprg",
            tasks = { h.task { argv = { "true" } } },
        }
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(bufnr)
        vim.keymap.set("n", "<localleader>ta", "<cmd>echo 'foreign'<cr>", {
            buffer = bufnr,
            desc = "foreign mapping only",
        })
        vim.bo[bufnr].filetype = "sample"

        assert.equal(
            "foreign mapping only",
            vim.fn.maparg(",ta", "n", false, true).desc
        )
        assert.is_not_nil(vim.api.nvim_buf_get_commands(bufnr, {
            builtin = false,
        }).SampleTestAll)
    end)

    it("repeated setup removes only owned registrations", function()
        local bufnr = h.buffer("sample", h.work "setup.sample")
        dispatch_kit.setup {
            tasks = { h.task { argv = { "true" } } },
        }
        assert.is_not_nil(
            vim.api.nvim_buf_get_commands(bufnr, {}).SampleTestAll
        )
        dispatch_kit.setup {}
        assert.is_nil(vim.api.nvim_buf_get_commands(bufnr, {}).SampleTestAll)
    end)

    it("validates task schemas", function()
        assert.has_error(function()
            dispatch_kit.setup {
                tasks = {
                    {
                        id = "",
                        filetypes = { "sample" },
                        actions = {},
                    },
                },
            }
        end, "non-empty id")
        assert.has_error(function()
            dispatch_kit.setup {
                tasks = {
                    {
                        id = "duplicate",
                        filetypes = { "sample" },
                        actions = {
                            {
                                name = "One",
                                desc = "one",
                                command = { argv = { "true" } },
                            },
                        },
                    },
                    {
                        id = "duplicate",
                        filetypes = { "sample" },
                        actions = {
                            {
                                name = "Two",
                                desc = "two",
                                command = { argv = { "true" } },
                            },
                        },
                    },
                },
            }
        end, "duplicate task id")
    end)
end)

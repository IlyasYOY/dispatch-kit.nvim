local h = require "tests.helpers"
local runner = require "dispatch-kit.runner"

describe("dispatch-kit runner", function()
    local original_cmd
    local original_notify

    before_each(function()
        original_cmd = vim.cmd
        original_notify = vim.notify
        runner.setup("auto", { bang = true, silent = true })
        h.reset_buffers()
    end)

    after_each(function()
        vim.cmd = original_cmd
        vim.notify = original_notify
        pcall(vim.api.nvim_del_user_command, "Dispatch")
        runner.setup("auto", { bang = true, silent = true })
        h.reset_buffers()
    end)

    it("shell-escapes structured argv", function()
        assert.equal(
            "'test' 'a b' '$HOME;true'",
            runner.shell_join { "test", "a b", "$HOME;true" }
        )
    end)

    it("rejects malformed command results", function()
        local messages = {}
        vim.notify = function(message)
            messages[#messages + 1] = message
        end
        assert.is_false(runner.run "invalid")
        assert.is_false(runner.run { argv = {} })
        assert.is_false(runner.run { argv = { "" } })
        assert.is_false(runner.run {
            argv = { "true" },
            compiler = "bad compiler",
        })
        assert.truthy(messages[1]:find("table with argv", 1, true))
        assert.truthy(messages[2]:find("must not be empty", 1, true))
        assert.truthy(messages[3]:find("non-empty string", 1, true))
        assert.truthy(messages[4]:find("compiler", 1, true))
    end)

    it("uses Dispatch when selected", function()
        local received
        vim.api.nvim_create_user_command("Dispatch", function(opts)
            received = opts.args
        end, { nargs = "*" })
        runner.setup "dispatch"
        assert.is_true(runner.run {
            argv = { "printf", "%s", "a b;$HOME" },
            cwd = h.work "project with spaces",
            compiler = "make",
        })
        assert.truthy(received:find("-compiler=make", 1, true))
        assert.truthy(received:find("-dir=", 1, true))
        assert.truthy(received:find("'a b;$HOME'", 1, true))
    end)

    it("reports unavailable Dispatch without loading it", function()
        local message
        vim.notify = function(value)
            message = value
        end
        runner.setup "dispatch"
        assert.is_false(runner.run { argv = { "true" } })
        assert.truthy(message:find(":Dispatch is unavailable", 1, true))
    end)

    it("builds every configured make command form", function()
        local bufnr = h.buffer("text", h.work "make-command.txt")

        local function capture(options)
            runner.setup("makeprg", options)
            local command
            vim.cmd = function(value)
                command = value
            end
            assert.is_true(runner.run { argv = { "true" }, bufnr = bufnr })
            vim.cmd = original_cmd
            return command
        end

        assert.equal("silent make!", capture { bang = true, silent = true })
        assert.equal("make", capture { bang = false, silent = false })
        assert.equal("make!", capture { bang = true, silent = false })
        assert.equal("silent make", capture { bang = false, silent = true })
    end)

    it("restores local compiler options after makeprg", function()
        local bufnr = h.buffer("text", h.work "fallback.txt")
        vim.bo[bufnr].makeprg = "original-command"
        vim.bo[bufnr].errorformat = "%f:%l:%m"
        vim.b[bufnr].current_compiler = "original"
        runner.setup("makeprg", { bang = true, silent = true })

        assert.is_true(runner.run {
            argv = { "printf", "ok" },
            bufnr = bufnr,
        })

        assert.equal("original-command", vim.bo[bufnr].makeprg)
        assert.equal("%f:%l:%m", vim.bo[bufnr].errorformat)
        assert.equal("original", vim.b[bufnr].current_compiler)
    end)

    it("validates backend names", function()
        assert.has_error(function()
            runner.setup "invalid"
        end, "invalid backend")
    end)
end)

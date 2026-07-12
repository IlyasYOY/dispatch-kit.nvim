local config = require "dispatch-kit.config"

describe("dispatch-kit config", function()
    it("resolves dependency-free defaults", function()
        assert.same({
            backend = "auto",
            makeprg = { bang = true, silent = true },
            tasks = {},
        }, config.resolve())
    end)

    it("keeps custom tasks and expands enabled adapters", function()
        local custom = {
            id = "custom",
            filetypes = { "text" },
            actions = {
                {
                    name = "CustomTask",
                    desc = "custom task",
                    command = { argv = { "true" } },
                },
            },
        }
        local resolved = config.resolve {
            tasks = { custom },
            adapters = {
                python = true,
                proto = true,
            },
        }
        assert.equal("custom", resolved.tasks[1].id)
        assert.truthy(#resolved.tasks > 2)
    end)

    it("resolves makeprg options independently", function()
        assert.same(
            { bang = false, silent = true },
            config.resolve({ makeprg = { bang = false } }).makeprg
        )
        assert.same(
            { bang = true, silent = false },
            config.resolve({ makeprg = { silent = false } }).makeprg
        )
    end)

    it("rejects unknown and malformed options", function()
        assert.has_error(function()
            config.resolve { unknown = true }
        end, "unknown setup option")
        assert.has_error(function()
            config.resolve { makeprg = false }
        end, "makeprg must be a table")
        assert.has_error(function()
            config.resolve { makeprg = { other = true } }
        end, "unknown makeprg option")
        assert.has_error(function()
            config.resolve { adapters = { unknown = true } }
        end, "unknown adapter")
        assert.has_error(function()
            config.resolve { adapters = { go = "yes" } }
        end, "must be true or a table")
    end)
end)

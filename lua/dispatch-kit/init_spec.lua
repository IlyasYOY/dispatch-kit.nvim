local dispatch_kit = require "dispatch-kit"
local h = require "tests.helpers"

describe("dispatch-kit setup", function()
    after_each(function()
        dispatch_kit.setup {}
        h.reset_buffers()
    end)

    it("attaches matching buffers that are already loaded", function()
        h.reset_buffers()
        local bufnr = h.buffer("sample", h.work "loaded.sample")
        dispatch_kit.setup {
            tasks = { h.task { argv = { "true" } } },
        }
        assert.is_not_nil(
            vim.api.nvim_buf_get_commands(bufnr, {}).SampleTestAll
        )
    end)

    it("rejects invalid backend configuration", function()
        assert.has_error(function()
            dispatch_kit.setup { backend = "invalid" }
        end, "invalid backend")
    end)
end)

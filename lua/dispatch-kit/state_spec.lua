local state = require "dispatch-kit.state"

describe("dispatch-kit repeat state", function()
    before_each(function()
        state.clear()
    end)

    after_each(function()
        state.clear()
    end)

    it("copies stored and returned command specs", function()
        local spec = {
            argv = { "test", "--all" },
            cwd = "/project",
            compiler = "make",
            bufnr = 3,
        }
        state.set("test", spec)
        spec.argv[1] = "changed"

        local stored = state.get "test"
        assert.same({
            argv = { "test", "--all" },
            cwd = "/project",
            compiler = "make",
            bufnr = 3,
        }, stored)

        stored.argv[1] = "changed-again"
        assert.equal("test", state.get("test").argv[1])
    end)

    it("clears all task state", function()
        state.set("test", { argv = { "test" } })
        state.clear()
        assert.is_nil(state.get "test")
    end)
end)

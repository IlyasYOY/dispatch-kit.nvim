local health = require "dispatch-kit.health"

local function capture_health()
    local reports = {}
    local captured = {}
    for _, level in ipairs { "start", "ok", "warn", "error", "info" } do
        captured[level] = function(message, advice)
            reports[#reports + 1] = {
                level = level,
                message = message,
                advice = advice,
            }
        end
    end
    return captured, reports
end

local function has_report(reports, level, fragment)
    for _, report in ipairs(reports) do
        if report.level == level and report.message:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

describe("dispatch-kit health", function()
    local original_health

    before_each(function()
        original_health = vim.health
    end)

    after_each(function()
        vim.health = original_health
    end)

    it("reports runtime APIs and optional Dispatch", function()
        local captured, reports = capture_health()
        vim.health = captured

        health.check()

        assert.truthy(has_report(reports, "start", "dispatch-kit.nvim"))
        assert.truthy(has_report(reports, "ok", "Neovim 0.11"))
        assert.truthy(has_report(reports, "ok", "nvim_buf_create_user_command"))
        assert.truthy(has_report(reports, "info", "vim-dispatch"))
    end)
end)

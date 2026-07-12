local util = require "dispatch-kit.adapters.util"

local M = {}

function M.tasks()
    return {
        {
            id = "proto.lint",
            filetypes = { "proto" },
            compiler = "make",
            actions = {
                util.action {
                    name = "ProtoLint",
                    scope = "file",
                    desc = "run protolint on the current file",
                    keymaps = { run = "<localleader>lp" },
                    command = function(ctx)
                        return {
                            argv = {
                                "protolint",
                                "lint",
                                "-reporter=unix",
                                util.buffer_path(ctx.bufnr, ":p"),
                            },
                        }
                    end,
                },
                util.action {
                    name = "ProtoLintBuf",
                    scope = "file",
                    desc = "run buf lint on the current file",
                    keymaps = { run = "<localleader>lb" },
                    command = function(ctx)
                        return {
                            argv = {
                                "buf",
                                "lint",
                                util.buffer_path(ctx.bufnr, ":p"),
                            },
                        }
                    end,
                },
            },
            repeat_last = util.repeat_last(
                "ProtoLintLast",
                "<localleader>ll",
                "Proto lint"
            ),
        },
    }
end

return M

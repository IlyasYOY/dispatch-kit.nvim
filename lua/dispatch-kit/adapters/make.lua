local ts = require "dispatch-kit.treesitter"
local util = require "dispatch-kit.adapters.util"

local M = {}

local function tree_root(bufnr)
    local parser = ts.parser(bufnr, "make")
    if not parser then
        return nil
    end
    local trees = parser:parse()
    return trees[1] and trees[1]:root() or nil
end

local function make_command(bufnr, target)
    return {
        argv = {
            "make",
            "-C",
            util.buffer_path(bufnr, ":p:h"),
            target,
        },
        compiler = "make",
    }
end

local function all_targets(bufnr)
    local root = tree_root(bufnr)
    if not root then
        return nil
    end
    local ok, query =
        pcall(vim.treesitter.query.parse, "make", "(rule (targets) @targets)")
    if not ok then
        util.notify "unable to parse the Make target query"
        return nil
    end

    local seen = {}
    local targets = {}
    for _, node in query:iter_captures(root, bufnr) do
        local text = vim.treesitter.get_node_text(node, bufnr)
        for target in text:gmatch "%S+" do
            if not seen[target] then
                seen[target] = true
                targets[#targets + 1] = target
            end
        end
    end
    table.sort(targets)
    return targets
end

local function current_target(bufnr)
    if not tree_root(bufnr) then
        return nil
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local ok, node = pcall(vim.treesitter.get_node, {
        bufnr = bufnr,
        pos = { cursor[1] - 1, cursor[2] },
    })
    if not ok then
        node = nil
    end
    while node and node:type() ~= "rule" do
        node = node:parent()
    end
    if not node then
        util.notify "cursor is not within a make target rule"
        return nil
    end

    for child in node:iter_children() do
        if child:type() == "targets" then
            return vim.treesitter.get_node_text(child, bufnr):match "%S+"
        end
    end
    util.notify "unable to parse the current make target"
end

function M.tasks()
    return {
        {
            id = "make.target",
            filetypes = { "make" },
            compiler = "make",
            actions = {
                util.action {
                    name = "MakeTargets",
                    scope = "all",
                    desc = "run a target from the current file",
                    keymaps = { run = "<localleader>T" },
                    command = function(ctx)
                        local targets = all_targets(ctx.bufnr)
                        if not targets or #targets == 0 then
                            util.notify "no targets found in Makefile"
                            return nil
                        end
                        return function(done)
                            vim.ui.select(
                                targets,
                                { prompt = "Select a make target:" },
                                function(choice)
                                    if choice then
                                        done(make_command(ctx.bufnr, choice))
                                    end
                                end
                            )
                        end
                    end,
                },
                util.action {
                    name = "MakeTarget",
                    scope = "current",
                    desc = "run the current make target",
                    keymaps = { run = "<localleader>t" },
                    command = function(ctx)
                        local target = current_target(ctx.bufnr)
                        return target and make_command(ctx.bufnr, target) or nil
                    end,
                },
            },
        },
    }
end

return M

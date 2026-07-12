local M = {}

local function check_function(name, value)
    if type(value) == "function" then
        vim.health.ok(name .. " is available")
    else
        vim.health.error(name .. " is not available")
    end
end

function M.check()
    vim.health.start "dispatch-kit.nvim"

    if vim.fn.has "nvim-0.11" == 1 then
        vim.health.ok "Neovim 0.11 or newer is available"
    else
        vim.health.error "dispatch-kit.nvim requires Neovim 0.11 or newer"
    end

    local loaded, module = pcall(require, "dispatch-kit")
    if loaded and type(module.setup) == "function" then
        vim.health.ok "dispatch-kit.nvim is available"
    else
        vim.health.error(
            "dispatch-kit.nvim could not be loaded",
            loaded and nil or tostring(module)
        )
    end

    check_function(
        "vim.api.nvim_buf_create_user_command",
        vim.api.nvim_buf_create_user_command
    )
    check_function("vim.treesitter.get_parser", vim.treesitter.get_parser)

    if vim.fn.exists ":Dispatch" == 2 then
        vim.health.ok "vim-dispatch is available"
    else
        vim.health.info "vim-dispatch is not installed; the auto backend will use makeprg"
    end

    vim.health.info "Adapter executables and Tree-sitter parsers are checked when actions run"
end

return M

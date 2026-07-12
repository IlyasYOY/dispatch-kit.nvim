if vim.g.loaded_dispatch_kit == 1 then
    return
end

if vim.fn.has "nvim-0.11" == 0 then
    error "dispatch-kit.nvim requires Neovim 0.11 or newer"
end

vim.g.loaded_dispatch_kit = 1

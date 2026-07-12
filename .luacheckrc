std = "luajit"
codes = true
max_line_length = false

ignore = {
    "122", -- Neovim option proxies are writable at runtime.
}

read_globals = {
    "vim",
}

# dispatch-kit.nvim

`dispatch-kit.nvim` creates buffer-local lint, test, build, and task commands
from declarative Lua definitions. It prefers
[vim-dispatch](https://github.com/tpope/vim-dispatch) when available and falls
back to Neovim's `makeprg`/quickfix workflow when it is not.

> [!IMPORTANT]
> This plugin is intentionally constrained by my personal Neovim workflow.
> Its scope and design decisions prioritize my own usage, so I may decline
> features that other users need. The project is MIT licensed, and you are
> welcome to fork it and adapt it to your workflow.

## Requirements

- Neovim 0.11 or newer
- `vim-dispatch` is optional and used by the default `auto` backend
- The bundled adapters require their corresponding command-line tools
- Tree-sitter parsers are optional and needed only for `current` actions and
  Makefile target discovery; the `nvim-treesitter` plugin itself is not required

Run `:checkhealth dispatch-kit` to verify the Neovim runtime APIs and report
whether optional vim-dispatch support is available. Adapter executables,
configuration files, and parsers remain action-specific and are checked when
their commands run.

## Installation

With Neovim 0.12 or newer, use the built-in `vim.pack`:

```lua
vim.pack.add {
    { src = "https://github.com/IlyasYOY/dispatch-kit.nvim" },
    { src = "https://github.com/tpope/vim-dispatch" }, -- optional
}
```

Neovim 0.11 users should install the plugin with lazy.nvim or another package
manager.

With lazy.nvim:

```lua
{
    "IlyasYOY/dispatch-kit.nvim",
    opts = {
        adapters = {
            go = true,
            python = true,
        },
    },
}
```

Nothing is registered until `setup()` enables an adapter or custom task.

## Configuration

```lua
require("dispatch-kit").setup {
    -- "auto" uses :Dispatch when available, otherwise temporary makeprg.
    -- "dispatch" and "makeprg" force one backend.
    backend = "auto",

    -- Options used only by the makeprg backend. These defaults preserve the
    -- original behavior: hide command output and do not jump to the first
    -- quickfix entry.
    makeprg = {
        bang = true,
        silent = true,
    },

    adapters = {
        go = {
            golangci = {
                -- Project-local configs win over this optional fallback.
                fallback_config = vim.fn.expand "~/.golangci.yml",
            },
        },
        java = {
            pmd = { config = "/path/to/pmd.xml" },
            checkstyle = { config = "/path/to/checkstyle.xml" },
        },
        python = true,
        javascript = true, -- JS, JSX, TypeScript, and TSX
        proto = true,
        make = true,
    },
}
```

All adapters are opt-in. Missing executables, Java lint configs, or Tree-sitter
parsers do not prevent the plugin from loading; the affected command reports
the problem when invoked.

## Declarative task API

Custom tasks use the same core as bundled adapters:

```lua
require("dispatch-kit").setup {
    tasks = {
        {
            id = "lua.test",
            filetypes = { "lua" },
            compiler = "make",
            actions = {
                {
                    name = "LuaTestAll",
                    scope = "all",
                    desc = "run all Lua tests",
                    bang = true,
                    count = 0,
                    keymaps = {
                        run = "<localleader>ta",
                        bang = "<localleader>tA",
                    },
                    command = function(ctx)
                        local argv = { "make", "test" }
                        if ctx.bang then
                            vim.list_extend(argv, { "VERBOSE=1" })
                        end
                        if ctx.count ~= 0 then
                            vim.list_extend(argv, { "REPEAT=" .. ctx.count })
                        end
                        return { argv = argv, cwd = vim.fn.getcwd() }
                    end,
                },
            },
            repeat_last = {
                name = "LuaTestLast",
                keymap = "<localleader>tl",
                desc = "repeat the last Lua test command",
            },
        },
    },
}
```

Task fields:

- `id`: unique state key; repeat state is shared across matching buffers
- `filetypes`: filetypes in which actions are registered
- `compiler`: optional default compiler, overridden by a command result
- `actions`: command declarations
- `repeat_last`: optional buffer-local repeat command and keymap

Action fields:

- `name`, `desc`, and `command` are required
- `scope` is descriptive and normally `all`, `package`, `file`, or `current`
- `bang`, `count`, and `nargs` use Neovim user-command semantics
- `keymaps.run` and `keymaps.bang` create normal-mode buffer-local mappings
- `command` is a command table or a function receiving
  `{ bufnr, scope, bang, count, args, fargs }`

A command table is `{ argv = string[], cwd?, compiler? }`. Arguments are
shell-escaped individually. Raw shell command strings are intentionally not
accepted. A builder may also return a deferred function accepting `done`; this
supports `vim.ui.select()` without weakening argument handling.

The resolved argv, cwd, and compiler are stored only after a successful launch.
`*Last` commands replay that exact result rather than invoking the builder or
re-detecting a compiler.

## Bundled commands

| Adapter | Commands |
| --- | --- |
| Go | `GoLangCiLint{All,Package,File,Last}`, `GoTest{All,Package,File,Function,Last}`, `GoBenchTest{All,Package,File,Function,Last}`, `GoBuild{All,Package,File,Last}` |
| Java | `JavaPMD`, `JavaCheckstyle`, `JavaLintLast`, `JavaTest{All,File,Function,Last}` |
| Python | `PythonTest{All,Package,File,Function,Last}` |
| JS/TS | `JSTest{All,Package,File,Function,Last}` |
| Proto | `ProtoLint`, `ProtoLintBuf`, `ProtoLintLast` |
| Make | `MakeTargets`, `MakeTarget` |

Default mappings use `<localleader>l` for lint, `<localleader>t` for tests,
`<localleader>m` for benchmarks, and `<localleader>b` for builds. Go bang
mappings use an uppercase final letter and pass the current count. Proto maps
protolint/buf/last to `lp`, `lb`, and `ll`; Make maps selection/current to `T`
and `t`.

## Backend behavior

The `dispatch` backend passes `compiler` and `cwd` to `:Dispatch`. The
`makeprg` backend runs synchronously through `:make`: it saves buffer-local
`makeprg`, `errorformat`, and compiler state, installs the resolved command,
loads quickfix results, and restores the original options even after failure.
`makeprg.bang` adds `!`, which prevents Neovim from jumping to the first
quickfix entry. `makeprg.silent` adds `:silent`, which hides command feedback.
Both options default to `true` and are independent from action-level `bang`.

Commands and mappings are always buffer-local. Re-running `setup()` removes
only registrations owned by dispatch-kit. A pre-existing foreign command or
mapping is preserved and produces a warning.

See `:help dispatch-kit` for the full reference.

## Development

```bash
make check
make test NVIM_VERSION=v0.11.7
make test NVIM_VERSION=v0.12.5
make test NVIM_VERSION=nightly
```

`make check` is non-mutating and runs Luacheck, StyLua validation, isolated
headless Neovim specs, and tracked Vim help validation.

## License

MIT. See [LICENSE](./LICENSE).

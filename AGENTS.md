# dispatch-kit.nvim Agent Guidelines

- Public setup and task-schema behavior lives under `lua/dispatch-kit/`.
- Bundled languages are optional modules under `lua/dispatch-kit/adapters/`.
- Support Neovim 0.11 and newer. `vim-dispatch` must remain optional.
- Keep task commands and mappings buffer-local and shell arguments structured.
- `make check` is the canonical formatting, lint, help, and test command.
- `make test NVIM_VERSION=v0.11.7` verifies minimum-version compatibility.
- Do not commit or push unless the user explicitly asks.

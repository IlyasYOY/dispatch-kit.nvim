# dispatch-kit.nvim Agent Guidelines

## Project shape

- Support Neovim 0.11 and newer.
- Public setup and task-schema behavior lives under `lua/dispatch-kit/`.
- Bundled languages are optional modules under
  `lua/dispatch-kit/adapters/`.
- Startup compatibility checks live in `plugin/dispatch-kit.lua`; setup is
  intentionally explicit.
- Unit specs are colocated as `*_spec.lua`. Cross-module adapter and runtime
  integration specs stay under `tests/`.

## Runtime contracts

- Keep task commands and mappings buffer-local. Repeated setup may remove only
  registrations owned by dispatch-kit.
- Keep command argv structured until the backend boundary. Raw shell command
  strings are rejected.
- Preserve task IDs, action schemas, command names, keymaps, repeat state,
  deferred builders, and adapter option shapes.
- `vim-dispatch` is optional. `auto` falls back to temporary buffer-local
  `makeprg`; the fallback must restore `makeprg`, `errorformat`, and
  compiler state even on failure.
- Missing executables, lint configs, and Tree-sitter parsers must not prevent
  setup. Report the problem only when the affected action is invoked.
- Keep adapters independent from personal dotfiles and environment variables.

## Development

- `make check` is the canonical non-mutating format, lint, help, and test
  command.
- `make test` runs all isolated module and integration specs.
- Before compatibility work is complete, run:
  - `make test NVIM_VERSION=v0.11.7`
  - `make test NVIM_VERSION=v0.12.5`
  - `make test NVIM_VERSION=nightly` as a compatibility probe
- A selected spec can be passed through
  `require("tests.runner").run({ files = { ... }, verbose = true })`.
- Use `tests.helpers` and ignored `.test-work` fixtures. Never read the
  user's dotfiles, projects, or editor state from a test.

## Style and documentation

- StyLua uses 4 spaces, 80 columns, Unix line endings, preferred double quotes,
  and omitted call parentheses where supported.
- Keep adapter builders focused and share path/executable helpers through
  `lua/dispatch-kit/adapters/util.lua`.
- Update `README.md`, `doc/dispatch-kit.txt`, tracked `doc/tags`, and
  health coverage when requirements or public behavior changes.

## Repository safety

- Do not commit, push, tag, publish, or dispatch a release unless the user
  explicitly asks.
- Preserve unrelated worktree changes and keep generated parser/test state
  ignored.

# gloss.nvim

> **Work in progress, pre-0.1.** The storage layer is built and tested; the
> user-facing commands are landing milestone by milestone (see DESIGN.md).

A per-project glossary for the jargon and acronyms your codebase actually
uses. Hover a term to see its definition in an editable float, add missing
ones as you go, share the glossary with your team by committing it, and
optionally let an AI provider of your choice propose definitions from
codebase context.

## Requirements

- Neovim 0.11+
- [kkharji/sqlite.lua](https://github.com/kkharji/sqlite.lua) and libsqlite3
  (optional: only needed for the global dictionary and out-of-repo project
  stores; in-repo glossaries are plain JSONL and need nothing)
- ripgrep (optional: richer context for AI providers)

## Install

lazy.nvim:

```lua
{
  "shawnbays/gloss.nvim",
  dependencies = { "kkharji/sqlite.lua" },
  opts = {},
}
```

## Quickstart

```lua
require("gloss").setup({ keymaps = true })  -- optional; everything works without setup()
```

Put the cursor on a term and press `<leader>gg` (or `:Gloss`): a known term
opens its definition in an editable float; an unknown one opens a prefilled
new-entry buffer. Write the definition, `:w`, pick project or global. `q`
closes. `:Gloss init -p` moves a project's glossary into the repo as
git-friendly JSONL so teammates get it on clone.

Optional: plug in any AI to draft definitions from codebase context. The
bundled CLI adapter turns any command into a provider, and nothing leaves
the machine until you run `:Gloss ai on` in that project:

```lua
require("gloss").setup({
  ai = { provider = require("gloss.providers.cli").new({ cmd = { "claude", "-p" } }) },
  on_miss = { "ai", "prompt" },
})
```

Proposals open in the review buffer marked as AI-sourced; nothing is saved
until you `:w`.

Working today: lookup, add, edit, delete, init/deinit with migration, the
keymap layers, cross-store fuzzy search (`:Gloss search #tag words`) with
copy/move between stores, `:Gloss list`, the projects browser, relink, AI
providers with the consent gate, and `:checkhealth gloss`. Landing next:
doctor/gc/export, the hover.nvim provider, and v0.1.0.

## Documentation

The manual is the source of depth: `:h gloss`. Design rationale lives in
[DESIGN.md](DESIGN.md).

## Development

```sh
make deps   # clone test dependencies into .deps/
make test   # run the suite headlessly
make lint   # stylua --check
```

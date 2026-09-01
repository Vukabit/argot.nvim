# argot.nvim

> **argot** (*AR-goh*; the t is silent): the insider vocabulary of a group.
> Every codebase has one. This plugin decodes it.

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
  "Vukabit/argot.nvim",
  dependencies = { "kkharji/sqlite.lua" },
  opts = {},
}
```

## Quickstart

```lua
require("argot").setup({ keymaps = true })  -- optional; everything works without setup()
```

Put the cursor on a term and press `<leader>gg` (or `:Argot`): a known term
opens its definition in an editable float; an unknown one opens a prefilled
new-entry buffer. Write the definition, `:w`, pick project or global. `q`
closes. `:Argot init -p` moves a project's glossary into the repo as
git-friendly JSONL so teammates get it on clone.

Optional: plug in any AI to draft definitions from codebase context. The
bundled CLI adapter turns any command into a provider, and nothing leaves
the machine until you run `:Argot ai on` in that project:

```lua
require("argot").setup({
  keymaps = true,
  ai = { provider = require("argot.providers.cli").new({ cmd = { "claude", "-p" } }) },
  on_miss = { "ai", "prompt" },
})
```

Proposals open in the review buffer marked as AI-sourced; nothing is saved
until you `:w`.

The full tour lives in the manual (`:h argot`): lookup and the editable
definition float, per-project and global stores (project definitions shadow
global ones), `[[term]]` cross-links between definitions (gd to follow,
CTRL-X CTRL-O to complete), in-repo mode with sane git merges, cross-store
fuzzy search with copy/move, the projects browser, relink for moved repos,
`:Argot doctor`/`gc`/`export`/`import`, `:Argot reset` (the nuclear option,
which archives instead of deleting), and `:checkhealth argot`. Integrations:
a cached statusline component (`require("argot").statusline()`), opt-in
extmark highlighting of known terms (`:Argot highlight`), a telescope
extension (`:Telescope argot` after `load_extension("argot")`; the search
keymap uses it automatically), and a
[hover.nvim](https://github.com/lewis6991/hover.nvim) provider module
(`"argot.providers.hover"` in hover's provider list).

## Documentation

The manual is the source of depth: `:h argot`. Design rationale lives in
[DESIGN.md](DESIGN.md).

## Development

```sh
make deps   # clone test dependencies into .deps/
make test   # run the suite headlessly
make lint   # stylua --check + selene + version-marker consistency
scripts/version.sh set 0.2.0   # bump every version marker at once
```

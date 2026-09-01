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

Nothing works yet beyond `:Gloss` subcommand completion and
`:checkhealth gloss`; this section fills in as milestones land.

## Documentation

The manual is the source of depth: `:h gloss`. Design rationale lives in
[DESIGN.md](DESIGN.md).

## Development

```sh
make deps   # clone test dependencies into .deps/
make test   # run the suite headlessly
make lint   # stylua --check
```

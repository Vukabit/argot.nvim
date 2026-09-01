# gloss.nvim design decisions

This file records *why* things are the way they are, ADR-style. The *how* lives
in `:h gloss`; the quickstart lives in the README. If a section here starts
explaining usage, it is leaking into the manual's job and should be cut.

## What this is

A per-project glossary for the jargon and acronyms a codebase actually uses.
Look up the word under the cursor, get a definition in an editable float, add
one when it is missing, optionally let a pluggable AI provider propose one from
codebase context. Named after the medieval *gloss*: a marginal note explaining
a difficult word.

## Storage: two adapters behind one interface

- **SQLite** (kkharji/sqlite.lua) for the global dictionary and out-of-repo
  project stores. Honest justification: WAL mode makes concurrent nvim
  instances safe, which JSON files handle badly.
- **JSONL only for in-repo mode** (`.gloss/glossary.jsonl`). A binary DB in
  git is all cost: no diffs, no review, unmergeable. JSONL lines are sorted by
  term and serialized with a fixed key order, so identical data produces
  identical bytes and a one-entry change is a one-line diff. First line is a
  version header. Recommended gitattribute `merge=union` makes the common
  conflict (two people added different terms) resolve itself; a true same-term
  conflict surfaces as a duplicate line, which the loader reports instead of
  dropping.
- Adapters do exact/alias retrieval only. Fuzzy search, case policy, and
  resolution order live above the storage layer, so both backends are
  automatically identical in capability.
- JSONL writes are atomic (tmp + rename) and reload-before-merge. Damaged
  lines are skipped on load, preserved verbatim on write, and reported by
  `:Gloss doctor`; the loader never destroys what it cannot parse.

## Project identity: registry, not path hash

Deriving a store location from the project path orphans the data the moment
the directory moves. Instead: out-of-repo DBs get permanent UUID filenames,
and a registry (`projects.json` in the data dir) maps identities to them.
Lookup order: exact root path, then normalized git remote URL (catches moves
and re-clones, with a confirm prompt before relinking). Git worktrees resolve
identity via `git rev-parse --git-common-dir`, so all worktrees of a repo
share one glossary. `:Gloss gc` only ever deletes after explicit confirmation.

## Nothing from the repo is ever executed

Entries are data; project config is `.gloss/config.json`, never Lua. This
removes the entire exrc-style trust problem (no `vim.secure.read`, no
prompts, no attack surface). Do not add a Lua config file to `.gloss/` later;
that would reintroduce the problem this decision deleted. Send-code-to-AI
consent is likewise per-user local state, never inherited from a file someone
else committed.

## Resolution pipeline

Lookup walks an ordered chain of sources, then an ordered chain of miss
handlers: `resolve = { "project", "global" }`, `on_miss = { "ai", "prompt" }`.
AI is not a subsystem, just one more handler; custom sources (a company wiki,
for example) drop into the list without touching core.

## AI provider contract

- Core never talks to a model. Providers implement one function:
  `propose(request, callback)` returning definition/expansion/confidence or a
  list of clarifying `questions` (one round-trip, capped).
- Core owns context gathering (surrounding lines, capped ripgrep hits of the
  term, README head) so every provider benefits equally.
- AI output is never auto-saved; proposals land in the editable review buffer
  marked `source = "ai"`.
- The reference adapter shells out to any CLI (prompt on stdin, JSON on
  stdout), so `claude -p`, `llm`, ollama, or a homegrown script all work with
  zero SDK dependencies.
- AI is inert until explicitly enabled per project (`:Gloss ai on`).

## Case policy for acronyms

Naive case-insensitive matching makes the English word "it" hit an "IT"
entry. Default policy: uppercase terms at or under 3 characters match
case-sensitively; longer terms match case-insensitively; per-entry override
and aliases cover exceptions.

## Definition buffer

The float shows a real buffer (`buftype=acwrite`, markdown with a small
`key: value` header block). Editing uses every motion the user owns; `:w`
persists via `BufWriteCmd`; add and edit are one code path. Exact header
format gets pinned when milestone 2 builds it.

## Keymaps: map frequency, not surface area

Admin commands (init, gc, import...) stay commands; deliberate typing is the
right interface for rare or destructive operations. Daily operations get a
three-layer treatment: `<Plug>` mappings for everything (no defaults ever
imposed), an opt-in curated set under a configurable prefix with per-action
override or `false`, and which-key group registration when present. The
curated installer never clobbers an existing mapping: it skips and reports
via `:checkhealth gloss`.

## Documentation

`:h gloss` is the manual and the single source of depth; the README is
quickstart only. CI includes a doc-drift check (every subcommand, `<Plug>`
map, and setup key must have a help tag, and vice versa) so the manual cannot
silently rot.

## Build order

1. Scaffold, tooling, storage adapters with tests (done)
2. Registry, init/deinit, lookup pipeline, definition buffer (daily-drivable)
3. Cross-DB fuzzy search with copy/move actions, list, projects
4. AI handler, CLI reference adapter, consent gate
5. doctor/gc/export, hover.nvim provider, full vimdoc, v0.1.0

## Out of scope for v0.1

Statusline component, telescope extension, extmark highlighting of known
terms, cross-linked definitions, FTS. All post-v0.1; none require design
changes.

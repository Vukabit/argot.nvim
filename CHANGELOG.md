# Changelog

## 0.1.0 (2026-09-01)

First cut. Everything in the manual works:

- lookup, add, edit, delete through the editable acwrite definition float
  (header + markdown body, rename via the term line)
- storage: SQLite for the global dictionary and out-of-repo project stores,
  git-friendly sorted JSONL for in-repo glossaries (`:Gloss init -p`),
  atomic writes, damaged lines preserved and reported
- project identity: UUID registry with git-remote relink for moved repos,
  worktrees share one glossary, `deinit` and migration both back up first
- case policy: short all-uppercase acronyms match case-sensitively, with
  per-entry overrides
- cross-store fuzzy search (`#tag` grammar) with edit/copy/move/delete
  actions, `:Gloss list`, the projects browser, `relink`
- AI providers: pluggable `propose(request, callback)` contract, bundled
  CLI adapter for any command, per-project consent gate (`:Gloss ai on`),
  one clarifying-questions round, proposals land as reviewable drafts
  marked ai / ai_edited
- maintenance: `doctor`, `gc` (confirmed, backed up), `export`/`import`,
  `:Gloss help`, `:checkhealth gloss`
- keymaps: <Plug> contract, opt-in curated set with per-key overrides and
  no-clobber install, automatic hover.nvim provider registration

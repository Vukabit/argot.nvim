# Changelog

## 0.1.0 (2026-09-01)

First cut. Everything in the manual works:

- lookup, add, edit, delete through the editable acwrite definition float
  (header + markdown body, rename via the term line)
- storage: SQLite for the global dictionary and out-of-repo project stores,
  git-friendly sorted JSONL for in-repo glossaries (`:Argot init -p`),
  atomic writes, damaged lines preserved and reported
- project identity: UUID registry with git-remote relink for moved repos,
  worktrees share one glossary, `deinit` and migration both back up first
- case policy: short all-uppercase acronyms match case-sensitively, with
  per-entry overrides
- cross-store fuzzy search (`#tag` grammar) with edit/copy/move/delete
  actions; `:Argot list` covers the whole lookup context (project entries
  shadow global ones); the projects browser; `relink`
- cross-links: `[[term]]` references between definitions; follow with gd
  or Enter (undefined targets open prefilled, so glossaries can be written
  links-first), complete after `[[` with CTRL-X CTRL-O, dangling links
  reported by doctor
- AI providers: pluggable `propose(request, callback)` contract, bundled
  CLI adapter for any command, per-project consent gate (`:Argot ai on`),
  one clarifying-questions round, proposals land as reviewable drafts
  marked ai / ai_edited
- maintenance: `doctor`, `gc` (confirmed, backed up), `export`/`import`,
  `:Argot reset project|global|all` (the nuclear option archives instead
  of deleting; "all" requires typing "wipe"), `:Argot help`,
  `:checkhealth argot`
- keymaps: <Plug> contract, opt-in curated set with per-key overrides and
  no-clobber install; hover.nvim provider module
- integrations: cached statusline component, opt-in extmark highlighting
  of known terms (case-policy aware), telescope extension with copy/move/
  delete mappings (the search keymap prefers it for a live fuzzy bar)

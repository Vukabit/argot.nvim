# Changelog

## 0.1.1 (2026-09-01)

Renamed from gloss.nvim to argot.nvim: four unrelated repos already carried
the old name, while argot (the insider vocabulary of a group) was untouched
in the editor ecosystem and names the problem rather than the mechanism.

- every user-facing surface renamed: `:Argot`, `<Plug>(Argot...)`,
  `argot.setup`, `:Telescope argot`, `argot.providers.*`, `.argot/`
  project dirs, the `Argot*` events and highlight groups
- migrations are automatic: the data directory moves itself from the old
  location on first run, and in-repo files with the old `{"gloss":1}`
  header load fine and pick up the new header on their next write
- github.com/Vukabit/gloss.nvim redirects to Vukabit/argot.nvim

## 0.1.0 (2026-09-01, as gloss.nvim)

Everything in the manual works:

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
  actions; `:Gloss list` covers the whole lookup context (project entries
  shadow global ones); the projects browser; `relink`
- AI providers: pluggable `propose(request, callback)` contract, bundled
  CLI adapter for any command, per-project consent gate (`:Gloss ai on`),
  one clarifying-questions round, proposals land as reviewable drafts
  marked ai / ai_edited
- maintenance: `doctor`, `gc` (confirmed, backed up), `export`/`import`,
  `:Gloss reset project|global|all` (the nuclear option archives instead
  of deleting; "all" requires typing "wipe"), `:Gloss help`,
  `:checkhealth gloss`
- keymaps: <Plug> contract, opt-in curated set with per-key overrides and
  no-clobber install; hover.nvim provider module
- integrations: cached statusline component, opt-in extmark highlighting
  of known terms (case-policy aware), telescope extension with copy/move/
  delete mappings (the search keymap prefers it for a live fuzzy bar)
- cross-links: `[[term]]` references between definitions; follow with gd
  or Enter (undefined targets open prefilled, so glossaries can be written
  links-first), complete after `[[` with CTRL-X CTRL-O, dangling links
  reported by doctor

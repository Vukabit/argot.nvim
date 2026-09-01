--- gloss.nvim: a per-project glossary for the jargon and acronyms your
--- codebase actually uses. Public API surface; see :h gloss.

local M = {}

M.version = "0.1.0"

--- Optional. gloss works with defaults if this is never called.
---@param opts table? see :h gloss.setup
function M.setup(opts)
  require("gloss.config").setup(opts)
  require("gloss.keymaps").install()
  -- legacy hover.nvim versions only; modern ones load the provider module
  -- "gloss.providers.hover" via hover's own config (see :h gloss-keymaps)
  require("gloss.hover").register()
end

--- Look up a word (default: the word under the cursor or visual selection).
---@param word string?
function M.lookup(word)
  require("gloss.lookup").run(word)
end

--- Open a new-entry buffer, optionally prefilled.
---@param term string?
function M.add(term)
  require("gloss.lookup").add(term)
end

--- Open an existing entry for editing.
---@param term string
function M.edit(term)
  require("gloss.lookup").edit(term)
end

return M

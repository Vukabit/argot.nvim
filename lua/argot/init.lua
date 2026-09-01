--- argot.nvim: a per-project glossary for the jargon and acronyms your
--- codebase actually uses. Public API surface; see :h argot.

local M = {}

M.version = "0.1.1"

--- Optional. argot works with defaults if this is never called.
---@param opts table? see :h argot.setup
function M.setup(opts)
  require("argot.config").setup(opts)
  require("argot.keymaps").install()
  -- legacy hover.nvim versions only; modern ones load the provider module
  -- "argot.providers.hover" via hover's own config (see :h argot-keymaps)
  require("argot.hover").register()
  if require("argot.config").options.highlight.enabled then
    require("argot.highlights").set(true)
  end
end

--- Statusline component: "argot:<count>" for the current project, or "".
---@return string
function M.statusline()
  return require("argot.statusline").component()
end

--- Look up a word (default: the word under the cursor or visual selection).
---@param word string?
function M.lookup(word)
  require("argot.lookup").run(word)
end

--- Open a new-entry buffer, optionally prefilled.
---@param term string?
function M.add(term)
  require("argot.lookup").add(term)
end

--- Open an existing entry for editing.
---@param term string
function M.edit(term)
  require("argot.lookup").edit(term)
end

return M

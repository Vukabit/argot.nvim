--- gloss.nvim: a per-project glossary for the jargon and acronyms your
--- codebase actually uses. Public API surface; see :h gloss.

local M = {}

--- Optional. gloss works with defaults if this is never called.
---@param opts table? see :h gloss.setup
function M.setup(opts)
  require("gloss.config").setup(opts)
end

return M

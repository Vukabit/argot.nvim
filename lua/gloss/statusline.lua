--- Statusline component: the current project's entry count, e.g. "gloss:12".
--- Returns "" when the project has no glossary, so it disappears rather
--- than nags. Aggressively cached: recomputed only when a gloss event or a
--- directory change invalidates it, never per redraw.

local M = {}

local cached = nil
local attached = false

local function attach()
  if attached then
    return
  end
  attached = true
  local group = vim.api.nvim_create_augroup("GlossStatusline", {})
  for _, pattern in ipairs({
    "GlossEntryAdded",
    "GlossEntryChanged",
    "GlossEntryRemoved",
    "GlossStoreChanged",
  }) do
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = pattern,
      callback = function()
        cached = nil
      end,
    })
  end
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      cached = nil
    end,
  })
end

--- Safe to call from a statusline expression: never prompts, never errors.
---@return string
function M.component()
  attach()
  if cached ~= nil then
    return cached
  end
  local ok, result = pcall(function()
    local handle = require("gloss.project").scope_store("project")
    if not handle then
      return ""
    end
    local count = #handle:list()
    return count > 0 and ("gloss:" .. count) or ""
  end)
  cached = (ok and result) or ""
  return cached
end

return M

--- [[term]] cross-links between definitions: a glossary where entries can
--- reference each other. Follow with gd (or <CR>) in the definition buffer;
--- a link to an undefined term offers to create it, so glossaries can be
--- written links-first. Complete link targets with CTRL-X CTRL-O after
--- typing "[[". `:Gloss doctor` reports dangling links.

local M = {}

--- Link targets in a definition body, in order of appearance.
---@param text string?
---@return string[]
function M.extract(text)
  local out = {}
  for target in (text or ""):gmatch("%[%[([^%[%]]-)%]%]") do
    target = vim.trim(target)
    if target ~= "" then
      out[#out + 1] = target
    end
  end
  return out
end

--- The [[link]] target under the cursor in the current window, if any.
---@return string?
function M.at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local init = 1
  while true do
    local first, last, target = line:find("%[%[([^%[%]]-)%]%]", init)
    if not first then
      return nil
    end
    if col >= first and col <= last then
      target = vim.trim(target)
      return target ~= "" and target or nil
    end
    init = last + 1
  end
end

local function term_candidates()
  local project = require("gloss.project")
  local out, seen = {}, {}
  for _, scope in ipairs(require("gloss.config").options.resolve) do
    local ok, handle = pcall(project.scope_store, scope)
    if ok and handle then
      local ok2, entries = pcall(handle.list, handle)
      if ok2 then
        for _, entry in ipairs(entries) do
          if not seen[entry.term] then
            seen[entry.term] = true
            out[#out + 1] = entry.term
          end
        end
      end
    end
  end
  table.sort(out)
  return out
end

--- 'omnifunc' for the definition buffer: complete term names after "[[",
--- closing the brackets on accept.
function M.omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local start = line:sub(1, col):find("%[%[[^%[%]]*$")
    if not start then
      return -3
    end
    return start + 1
  end
  local matches = {}
  for _, term in ipairs(term_candidates()) do
    if vim.startswith(term:lower(), (base or ""):lower()) then
      matches[#matches + 1] = { word = term .. "]]", abbr = term }
    end
  end
  return matches
end

return M

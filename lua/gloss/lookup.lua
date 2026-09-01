--- The lookup pipeline: word under cursor (or visual selection) -> ordered
--- store chain -> definition buffer on a hit, miss-handler chain otherwise.
--- Case policy lives here, above the storage layer.

local config = require("gloss.config")
local defbuf = require("gloss.defbuf")
local store = require("gloss.store")

local M = {}

--- Case policy: a stored short, all-uppercase acronym never matches
--- case-insensitively (so the English word "it" cannot hit an "IT" entry);
--- per-entry `case_sensitive` overrides in either direction.
local function ci_allowed(entry, case_cfg)
  if entry.case_sensitive == true then
    return false
  end
  if entry.case_sensitive == false then
    return true
  end
  local term = entry.term or ""
  local short = (case_cfg and case_cfg.short_acronym_len) or 3
  if #term <= short and term == term:upper() and term ~= term:lower() then
    return false
  end
  return true
end

---@param entries GlossEntry[]
---@param word string
---@param case_cfg? table
---@return GlossEntry?
function M.policy_match(entries, word, case_cfg)
  local _, exact = store.match(entries, word)
  if exact then
    return exact
  end
  local lower = word:lower()
  for _, entry in ipairs(entries) do
    if ci_allowed(entry, case_cfg) then
      local candidates = { entry.term }
      vim.list_extend(candidates, entry.aliases or {})
      for _, candidate in ipairs(candidates) do
        if candidate:lower() == lower then
          return entry
        end
      end
    end
  end
end

--- The word to look up: visual selection when one is active (multi-word
--- terms), command range marks, else <cword>.
---@param opts? {range?: boolean}
---@return string
function M.word(opts)
  if opts and opts.range then
    local lines = vim.fn.getregion(vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = vim.fn.visualmode() })
    return vim.trim(table.concat(lines, " "):gsub("%s+", " "))
  end
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    return vim.trim(table.concat(lines, " "):gsub("%s+", " "))
  end
  return vim.fn.expand("<cword>")
end

--- Walk the resolve chain for a word.
---@param word string
---@return GlossEntry? entry, table? store, string? scope
function M.find(word)
  local project = require("gloss.project")
  for _, scope in ipairs(config.options.resolve) do
    local handle = project.scope_store(scope, { interactive = scope == "project" })
    if handle then
      local entry = M.policy_match(handle:list(), word, config.options.case)
      if entry then
        return entry, handle, scope
      end
    end
  end
end

---@param word string?
---@param opts? {range?: boolean}
function M.run(word, opts)
  word = word and vim.trim(word) or M.word(opts)
  if word == "" then
    vim.notify("gloss: nothing to look up", vim.log.levels.WARN)
    return
  end
  local entry, handle, scope = M.find(word)
  if entry then
    return defbuf.open(entry, { store = handle, scope = scope })
  end
  for _, handler in ipairs(config.options.on_miss) do
    if handler == "prompt" then
      return M.add(word)
    elseif handler == "ai" then
      -- falls through to the next handler when no provider is configured
      -- or this project has not consented
      if require("gloss.ai").propose_for(word) then
        return
      end
    end
  end
  vim.notify(("gloss: no definition for %q"):format(word), vim.log.levels.INFO)
end

---@param term string?
function M.add(term)
  return defbuf.open({ term = term or "", definition = "" }, {})
end

---@param term string?
function M.edit(term)
  if not term or term == "" then
    vim.notify("gloss: :Gloss edit needs a term", vim.log.levels.ERROR)
    return
  end
  local entry, handle, scope = M.find(term)
  if not entry then
    vim.notify(("gloss: no entry %q (try :Gloss add %s)"):format(term, term), vim.log.levels.WARN)
    return
  end
  return defbuf.open(entry, { store = handle, scope = scope })
end

---@param term string?
function M.delete(term)
  if not term or term == "" then
    vim.notify("gloss: :Gloss delete needs a term", vim.log.levels.ERROR)
    return
  end
  local entry, handle, scope = M.find(term)
  if not entry then
    vim.notify(("gloss: no entry %q"):format(term), vim.log.levels.WARN)
    return
  end
  if vim.fn.confirm(("Delete %q from the %s store?"):format(entry.term, scope), "&Yes\n&No", 2) ~= 1 then
    return
  end
  handle:delete(entry.term)
  require("gloss.events").emit("GlossEntryRemoved", { term = entry.term, scope = scope })
  vim.notify(("gloss: deleted %q"):format(entry.term))
end

return M

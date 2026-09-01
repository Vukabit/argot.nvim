--- The definition buffer: a floating window around a real acwrite buffer,
--- so editing a definition uses every motion and plugin the user owns.
--- :w persists through BufWriteCmd; add and edit are one code path.
---
--- Round-trip format (:h argot-buffer): a `key: value` header block (term,
--- expansion, aliases, tags), one blank line, then the markdown definition.

local events = require("argot.events")

local M = {}

-- per-buffer save context
local contexts = {}
-- open buffers by display name, for reuse instead of duplicate floats
local by_name = {}

local HEADER_KEYS = { "term", "expansion", "aliases", "tags" }
local KNOWN = {}
for _, key in ipairs(HEADER_KEYS) do
  KNOWN[key] = true
end

local function split_list(value)
  local out = {}
  for item in (value or ""):gmatch("[^,]+") do
    item = vim.trim(item)
    if item ~= "" then
      out[#out + 1] = item
    end
  end
  return out
end

---@param entry table
---@return string[] lines all header keys are always shown, for editability
function M.serialize(entry)
  local lines = {
    "term: " .. (entry.term or ""),
    "expansion: " .. (entry.expansion or ""),
    "aliases: " .. table.concat(entry.aliases or {}, ", "),
    "tags: " .. table.concat(entry.tags or {}, ", "),
    "",
  }
  vim.list_extend(lines, vim.split(entry.definition or "", "\n", { plain = true }))
  return lines
end

---@param lines string[]
---@return table? entry, string? err
function M.parse(lines)
  local entry = { aliases = {}, tags = {} }
  local body_from
  for i, line in ipairs(lines) do
    if vim.trim(line) == "" then
      body_from = i + 1
      break
    end
    local key, value = line:match("^(%w+):%s?(.*)$")
    if not key then
      return nil,
        ("line %d is not a 'key: value' header line (a blank line must separate the header from the definition)"):format(
          i
        )
    end
    key = key:lower()
    if not KNOWN[key] then
      return nil, ("unknown header key %q on line %d"):format(key, i)
    end
    value = vim.trim(value)
    if key == "aliases" or key == "tags" then
      entry[key] = split_list(value)
    elseif value ~= "" then
      entry[key] = value
    end
  end
  if not entry.term or entry.term == "" then
    return nil, "the 'term' header is required"
  end
  local body = body_from and table.concat(vim.list_slice(lines, body_from), "\n") or ""
  entry.definition = body:gsub("%s+$", "")
  return entry
end

--- Open (or focus) the definition buffer for an entry.
---@param entry table full entry, or { term, definition } for a new one
---@param ctx? {store?: table, scope?: string}
---@return integer buf, integer win
function M.open(entry, ctx)
  ctx = ctx or {}
  local term = entry.term ~= nil and entry.term or ""
  -- sanitized names get a hash suffix so "C#" and "C%" never share a buffer
  local raw = term ~= "" and term or "new"
  local safe = raw:gsub("[^%w%-_.]", "_")
  if safe ~= raw then
    safe = safe .. "-" .. vim.fn.sha256(raw):sub(1, 6)
  end
  local name = ("argot://%s/%s"):format(ctx.scope or "unsaved", safe)

  local buf = by_name[name]
  local reuse = buf and vim.api.nvim_buf_is_loaded(buf) and contexts[buf]
  if reuse and not vim.bo[buf].modified then
    -- unchanged buffer: refresh from the (possibly newer) entry and context
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.serialize(entry))
    vim.bo[buf].modified = false
    contexts[buf] = { store = ctx.store, scope = ctx.scope, orig = vim.deepcopy(entry) }
  end
  if not reuse then
    buf = vim.api.nvim_create_buf(false, false)
    by_name[name] = buf
    pcall(vim.api.nvim_buf_set_name, buf, name)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.serialize(entry))
    vim.bo[buf].buftype = "acwrite"
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].swapfile = false
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].modified = false
    contexts[buf] = { store = ctx.store, scope = ctx.scope, orig = vim.deepcopy(entry) }

    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = buf,
      callback = function()
        M._save(buf)
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      callback = function()
        contexts[buf] = nil
        by_name[name] = nil
      end,
    })
  end

  local width = math.min(72, math.max(40, vim.o.columns - 8))
  local line_count = vim.api.nvim_buf_line_count(buf)
  local height = math.min(math.max(line_count + 1, 8), math.max(8, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2 - 1)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    title = (" argot: %s "):format(term ~= "" and term or "new entry"),
    title_pos = "center",
  })
  vim.wo[win].wrap = true

  vim.keymap.set("n", "q", function()
    if vim.bo[buf].modified then
      vim.notify("argot: unsaved changes (:w to save, :bd! to discard)", vim.log.levels.WARN)
      return
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, false)
    end
  end, { buffer = buf, desc = "argot: close" })

  -- [[link]] support: follow, complete, and see them
  vim.bo[buf].omnifunc = "v:lua.require'argot.links'.omnifunc"
  vim.api.nvim_set_hl(0, "ArgotLink", { default = true, underline = true })
  vim.fn.matchadd("ArgotLink", "\\[\\[[^][]\\{-}]]")
  for _, lhs in ipairs({ "gd", "<CR>" }) do
    vim.keymap.set("n", lhs, function()
      M._follow(buf, win)
    end, { buffer = buf, desc = "argot: follow link" })
  end

  -- land the cursor somewhere useful: the empty term, or the body
  if term == "" then
    vim.api.nvim_win_set_cursor(win, { 1, 6 })
  else
    vim.api.nvim_win_set_cursor(win, { math.min(6, line_count), 0 })
  end
  return buf, win
end

--- Follow the [[link]] under the cursor: open its entry, or a prefilled
--- new-entry buffer when the target is not defined yet (glossaries can be
--- written links-first). Refuses to abandon unsaved edits.
---@param buf integer
---@param win integer
---@return boolean handled true when the cursor was on a link
function M._follow(buf, win)
  local target = require("argot.links").at_cursor()
  if not target then
    return false
  end
  if vim.bo[buf].modified then
    vim.notify("argot: save (:w) or discard (:bd!) before following a link", vim.log.levels.WARN)
    return true
  end
  local entry, handle, scope = require("argot.lookup").find(target)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, false)
  end
  if entry then
    M.open(entry, { store = handle, scope = scope })
  else
    vim.notify(("argot: %q is not defined yet"):format(target), vim.log.levels.INFO)
    M.open({ term = target, definition = "" }, {})
  end
  return true
end

--- Resolve a store for a chosen scope on first save. Split out so tests
--- (and later callers) can substitute it.
---@param scope "project"|"global"
---@return table? store, string? err
function M._scope_store(scope)
  local project = require("argot.project")
  if scope == "global" then
    local s = project.global_store()
    if not s then
      return nil, "global store unavailable (kkharji/sqlite.lua and libsqlite3 required)"
    end
    return s
  end
  local s = project.project_store({ interactive = true })
  if not s then
    -- unregistered: saving to the project scope is registration intent
    local ok, err = pcall(project.register)
    if not ok then
      return nil, tostring(err)
    end
    local ok2, handle = pcall(project.project_store, {})
    if ok2 and handle then
      return handle
    end
    return nil, "could not open the project store (is sqlite.lua installed?)"
  end
  return s
end

function M._save(buf)
  local ctx = contexts[buf]
  if not ctx then
    return
  end
  local parsed, err = M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if not parsed then
    vim.notify("argot: " .. err, vim.log.levels.ERROR)
    return
  end
  -- history carries through edits; an AI proposal accepted verbatim stays
  -- "ai", a touched one becomes "ai_edited"
  parsed.created_at = ctx.orig.created_at
  if ctx.orig.source == "ai" then
    local untouched = parsed.definition == (ctx.orig.definition or "")
      and parsed.expansion == ctx.orig.expansion
    parsed.source = untouched and "ai" or "ai_edited"
  else
    parsed.source = ctx.orig.source
  end

  if ctx.store then
    M._persist(buf, ctx, parsed)
    return
  end
  vim.ui.select({ "project", "global" }, { prompt = ("Save %q to:"):format(parsed.term) }, function(choice)
    if not choice then
      return
    end
    local handle, serr = M._scope_store(choice)
    if not handle then
      vim.notify("argot: " .. (serr or ("no " .. choice .. " store available")), vim.log.levels.ERROR)
      return
    end
    ctx.store, ctx.scope = handle, choice
    M._persist(buf, ctx, parsed)
  end)
end

function M._persist(buf, ctx, parsed)
  -- the store handle may have been retired under us (:Argot init -p, gc);
  -- surface that instead of erroring out of BufWriteCmd and losing the edit
  local ok, saved = pcall(ctx.store.upsert, ctx.store, parsed)
  if not ok then
    vim.notify(
      "argot: could not save (the store may have been retired; reopen the entry): " .. tostring(saved),
      vim.log.levels.ERROR
    )
    return
  end
  if ctx.orig.term and ctx.orig.term ~= "" and ctx.orig.term ~= parsed.term then
    -- the term header was edited: this is a rename. terms_only, so keeping
    -- the old spelling as an alias of the new entry never deletes the save
    pcall(ctx.store.delete, ctx.store, ctx.orig.term, { terms_only = true })
  end
  local added = ctx.orig.created_at == nil
  ctx.orig = saved
  if vim.api.nvim_buf_is_loaded(buf) then
    vim.bo[buf].modified = false
  end
  events.emit(added and "ArgotEntryAdded" or "ArgotEntryChanged", { term = saved.term, scope = ctx.scope })
  vim.notify(("argot: saved %q to the %s store"):format(saved.term, ctx.scope or "current"))
end

return M

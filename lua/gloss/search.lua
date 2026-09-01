--- Cross-store search: one engine over every store gloss knows about (the
--- current project, the global dictionary, every registered project).
--- Adapters only provide list(); fuzzy matching is vim.fn.matchfuzzy over a
--- term/aliases/expansion/tags haystack, `#tag` tokens filter exactly, and
--- definition bodies get plain substring matching (fuzzy over prose is
--- noise). The UI is two-stage vim.ui.select chains, so it works on bare
--- Neovim and inherits any picker plugin the user runs.

local events = require("gloss.events")

local M = {}

---@class GlossSearchItem
---@field entry GlossEntry
---@field store table
---@field label string display name of the owning store
---@field scope "project"|"global"|"other"

--- Every reachable store, deduplicated, with unique display labels.
---@param opts? {startpath?: string}
---@return {label: string, scope: string, store: table, key: string}[]
function M.sources(opts)
  opts = opts or {}
  local project = require("gloss.project")
  local sources, seen_keys, seen_labels = {}, {}, {}

  local function add(label, scope, handle, key)
    if not handle or seen_keys[key] then
      return
    end
    seen_keys[key] = true
    if seen_labels[label] then
      seen_labels[label] = seen_labels[label] + 1
      label = ("%s (%d)"):format(label, seen_labels[label])
    else
      seen_labels[label] = 1
    end
    sources[#sources + 1] = { label = label, scope = scope, store = handle, key = key }
  end

  local cur_handle, cur_desc = project.project_store({ startpath = opts.startpath })
  if cur_handle then
    add(vim.fs.basename(cur_desc.root), "project", cur_handle, "path:" .. (cur_desc.path or ""))
  end
  add("global", "global", project.global_store(), "global")

  local reg = project.load_registry()
  local ids = {}
  for id in pairs(reg.projects) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    if not (cur_desc and cur_desc.registry_id == id) then
      local path = vim.fs.joinpath(project.data_paths().projects, id .. ".db")
      if vim.uv.fs_stat(path) then
        local ok, handle = pcall(project.store_for, { backend = "sqlite", path = path })
        if ok and handle then
          add(vim.fs.basename(reg.projects[id].root), "other", handle, "path:" .. path)
        end
      end
    end
  end
  return sources
end

---@param opts? {startpath?: string}
---@return GlossSearchItem[]
function M.collect(opts)
  local items = {}
  for _, src in ipairs(M.sources(opts)) do
    for _, entry in ipairs(src.store:list()) do
      items[#items + 1] = { entry = entry, store = src.store, label = src.label, scope = src.scope }
    end
  end
  return items
end

---@param query string?
---@return {tags: string[], needle: string}
function M.parse_query(query)
  local tags, words = {}, {}
  for token in (query or ""):gmatch("%S+") do
    local tag = token:match("^#(.+)$")
    if tag then
      tags[#tags + 1] = tag:lower()
    else
      words[#words + 1] = token
    end
  end
  return { tags = tags, needle = table.concat(words, " ") }
end

--- Pure filter: tag tokens are exact (case-insensitive), the rest fuzzy over
--- term/aliases/expansion/tags, then definition substring hits appended.
---@param items GlossSearchItem[]
---@param query string?
---@return GlossSearchItem[]
function M.filter(items, query)
  local q = M.parse_query(query)
  if #q.tags > 0 then
    items = vim.tbl_filter(function(item)
      local have = {}
      for _, tag in ipairs(item.entry.tags or {}) do
        have[tag:lower()] = true
      end
      for _, want in ipairs(q.tags) do
        if not have[want] then
          return false
        end
      end
      return true
    end, items)
  end
  if q.needle == "" then
    return items
  end
  local haystacks = {}
  for i, item in ipairs(items) do
    haystacks[#haystacks + 1] = {
      i = i,
      text = table.concat({
        item.entry.term,
        table.concat(item.entry.aliases or {}, " "),
        item.entry.expansion or "",
        table.concat(item.entry.tags or {}, " "),
      }, " "),
    }
  end
  local out, seen = {}, {}
  for _, hit in ipairs(vim.fn.matchfuzzy(haystacks, q.needle, { key = "text" })) do
    out[#out + 1] = items[hit.i]
    seen[hit.i] = true
  end
  local sub = q.needle:lower()
  for i, item in ipairs(items) do
    if not seen[i] and (item.entry.definition or ""):lower():find(sub, 1, true) then
      out[#out + 1] = item
    end
  end
  return out
end

---@param item GlossSearchItem
---@return string
function M.format_item(item)
  local entry = item.entry
  local line = entry.term
  if entry.expansion then
    line = line .. " - " .. entry.expansion
  end
  line = line .. ("  [%s]"):format(item.label)
  if entry.tags and #entry.tags > 0 then
    line = line .. "  #" .. table.concat(entry.tags, " #")
  end
  return line
end

--- Copy an entry into another store.
---@param entry GlossEntry
---@param dst table destination store
---@param opts? {on_collision?: "overwrite"|"keep_both"|"cancel"}
---@return boolean done
function M.copy(entry, dst, opts)
  local target = vim.deepcopy(entry)
  if dst:get(entry.term) then
    local choice = (opts and opts.on_collision) or "cancel"
    if choice == "cancel" then
      return false
    end
    if choice == "keep_both" then
      target.term = entry.term .. " (copy)"
    end
  end
  dst:upsert(target)
  return true
end

---@param entry GlossEntry
---@param src table source store
---@param dst table destination store
---@param opts? {on_collision?: "overwrite"|"keep_both"|"cancel"}
---@return boolean done
function M.move(entry, src, dst, opts)
  if not M.copy(entry, dst, opts) then
    return false
  end
  src:delete(entry.term)
  return true
end

--- :Gloss search entry point.
---@param query string?
function M.run(query)
  query = query or ""
  local items = M.filter(M.collect(), query)
  if #items == 0 then
    vim.notify(
      "gloss: nothing matches" .. (query ~= "" and (" " .. vim.inspect(query)) or ""),
      vim.log.levels.INFO
    )
    return
  end
  local prompt = query ~= "" and ("gloss search [%s]"):format(query) or "gloss search"
  vim.ui.select(items, { prompt = prompt, format_item = M.format_item }, function(item)
    if item then
      M.actions(item)
    end
  end)
end

local ACTIONS = { "edit", "copy to...", "move to...", "delete", "reveal origin" }

---@param item GlossSearchItem
function M.actions(item)
  vim.ui.select(ACTIONS, { prompt = item.entry.term .. " [" .. item.label .. "]" }, function(choice)
    if choice == "edit" then
      require("gloss.defbuf").open(item.entry, { store = item.store, scope = item.label })
    elseif choice == "copy to..." then
      M._pick_destination(item, false)
    elseif choice == "move to..." then
      M._pick_destination(item, true)
    elseif choice == "delete" then
      if
        vim.fn.confirm(("Delete %q from [%s]?"):format(item.entry.term, item.label), "&Yes\n&No", 2) == 1
      then
        item.store:delete(item.entry.term)
        events.emit("GlossEntryRemoved", { term = item.entry.term, scope = item.label })
        vim.notify(("gloss: deleted %q from [%s]"):format(item.entry.term, item.label))
      end
    elseif choice == "reveal origin" then
      vim.notify(
        ("gloss: %q lives in [%s] at %s"):format(item.entry.term, item.label, item.store.path or "?")
      )
    end
  end)
end

function M._pick_destination(item, is_move)
  local dests = vim.tbl_filter(function(src)
    return src.store ~= item.store
  end, M.sources())
  if #dests == 0 then
    vim.notify("gloss: no other store to send this to", vim.log.levels.WARN)
    return
  end
  local verb = is_move and "Move" or "Copy"
  vim.ui.select(dests, {
    prompt = ("%s %q to:"):format(verb, item.entry.term),
    format_item = function(dest)
      return dest.label
    end,
  }, function(dest)
    if not dest then
      return
    end
    local opts = {}
    if dest.store:get(item.entry.term) then
      local choice = vim.fn.confirm(
        ("%q already exists in [%s]"):format(item.entry.term, dest.label),
        "&Overwrite\n&Keep both\n&Cancel",
        3
      )
      if choice == 1 then
        opts.on_collision = "overwrite"
      elseif choice == 2 then
        opts.on_collision = "keep_both"
      else
        return
      end
    end
    local done
    if is_move then
      done = M.move(item.entry, item.store, dest.store, opts)
    else
      done = M.copy(item.entry, dest.store, opts)
    end
    if done then
      events.emit("GlossEntryAdded", { term = item.entry.term, scope = dest.label })
      if is_move then
        events.emit("GlossEntryRemoved", { term = item.entry.term, scope = item.label })
      end
      vim.notify(
        ("gloss: %s %q to [%s]"):format(is_move and "moved" or "copied", item.entry.term, dest.label)
      )
    end
  end)
end

--- :Gloss list: the current project's entries, optionally tag-filtered.
---@param query string?
function M.list(query)
  local project = require("gloss.project")
  local handle, desc = project.project_store({ interactive = true })
  if not handle then
    vim.notify("gloss: this project has no glossary yet (:Gloss add, or :Gloss init)", vim.log.levels.INFO)
    return
  end
  local label = vim.fs.basename(desc.root)
  local items = {}
  for _, entry in ipairs(handle:list()) do
    items[#items + 1] = { entry = entry, store = handle, label = label, scope = "project" }
  end
  items = M.filter(items, query)
  if #items == 0 then
    vim.notify(
      "gloss: no entries" .. ((query and query ~= "") and (" matching " .. query) or ""),
      vim.log.levels.INFO
    )
    return
  end
  vim.ui.select(items, { prompt = "gloss: " .. label, format_item = M.format_item }, function(item)
    if item then
      require("gloss.defbuf").open(item.entry, { store = item.store, scope = "project" })
    end
  end)
end

--- :Gloss projects: browse every project glossary from anywhere.
function M.projects()
  local sources = vim.tbl_filter(function(src)
    return src.scope ~= "global"
  end, M.sources())
  if #sources == 0 then
    vim.notify("gloss: no project glossaries known yet", vim.log.levels.INFO)
    return
  end
  vim.ui.select(sources, {
    prompt = "gloss projects",
    format_item = function(src)
      return ("%s (%d entries)"):format(src.label, #src.store:list())
    end,
  }, function(src)
    if not src then
      return
    end
    local items = {}
    for _, entry in ipairs(src.store:list()) do
      items[#items + 1] = { entry = entry, store = src.store, label = src.label, scope = src.scope }
    end
    if #items == 0 then
      vim.notify(("gloss: [%s] is empty"):format(src.label), vim.log.levels.INFO)
      return
    end
    vim.ui.select(items, { prompt = "gloss: " .. src.label, format_item = M.format_item }, function(item)
      if item then
        M.actions(item)
      end
    end)
  end)
end

--- Distinct tags across stores, for command completion.
---@param scope "all"|"project"
---@return string[]
function M.tag_candidates(scope)
  local items
  if scope == "project" then
    local handle = require("gloss.project").project_store({})
    items = {}
    for _, entry in ipairs(handle and handle:list() or {}) do
      items[#items + 1] = { entry = entry }
    end
  else
    items = M.collect()
  end
  local seen, tags = {}, {}
  for _, item in ipairs(items) do
    for _, tag in ipairs(item.entry.tags or {}) do
      if not seen[tag] then
        seen[tag] = true
        tags[#tags + 1] = "#" .. tag
      end
    end
  end
  table.sort(tags)
  return tags
end

return M

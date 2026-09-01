--- :Gloss subcommand dispatch and completion. Subcommands are registered
--- here as milestones land; unimplemented ones respond honestly instead of
--- failing silently.

local M = {}

local SUBCOMMANDS = {
  "lookup",
  "add",
  "edit",
  "delete",
  "list",
  "search",
  "init",
  "deinit",
  "projects",
  "relink",
  "gc",
  "export",
  "import",
  "ai",
  "highlight",
  "doctor",
  "help",
}

local handlers = {}

handlers.lookup = function(cmd)
  require("gloss.lookup").run(cmd.fargs[2], { range = cmd.range and cmd.range > 0 or nil })
end

handlers.add = function(cmd)
  require("gloss.lookup").add(cmd.fargs[2])
end

handlers.edit = function(cmd)
  require("gloss.lookup").edit(cmd.fargs[2])
end

handlers.delete = function(cmd)
  require("gloss.lookup").delete(cmd.fargs[2])
end

handlers.search = function(cmd)
  require("gloss.search").run(table.concat(vim.list_slice(cmd.fargs, 2), " "))
end

handlers.list = function(cmd)
  require("gloss.search").list(table.concat(vim.list_slice(cmd.fargs, 2), " "))
end

handlers.projects = function()
  require("gloss.search").projects()
end

handlers.relink = function()
  local project = require("gloss.project")
  local desc = project.resolve()
  if desc.mode == "in_repo" then
    vim.notify(
      "gloss: in-repo projects need no relinking (identity is the checked-out .gloss/)",
      vim.log.levels.INFO
    )
    return
  end
  if desc.relink then
    local msg = ("Relink this repo to its existing glossary (previously at %s)?"):format(desc.relink.old_root)
    if vim.fn.confirm(msg, "&Yes\n&No", 1) == 1 then
      project.relink(desc.relink.id, desc.root)
      require("gloss.events").emit("GlossStoreChanged", {})
      vim.notify("gloss: relinked")
    end
    return
  end
  if desc.registry_id then
    vim.notify("gloss: this project is already linked", vim.log.levels.INFO)
    return
  end
  local reg = project.load_registry()
  local ids = {}
  for id in pairs(reg.projects) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  if #ids == 0 then
    vim.notify("gloss: the registry is empty; nothing to relink to", vim.log.levels.INFO)
    return
  end
  vim.ui.select(ids, {
    prompt = "Relink this directory to which project?",
    format_item = function(id)
      return reg.projects[id].root
    end,
  }, function(id)
    if not id then
      return
    end
    project.relink(id, desc.root)
    require("gloss.events").emit("GlossStoreChanged", {})
    vim.notify(("gloss: relinked %s here"):format(reg.projects[id].root))
  end)
end

handlers.init = function(cmd)
  local project = require("gloss.project")
  local events = require("gloss.events")
  local desc = project.resolve()
  if desc.relink then
    local msg = ("gloss: found an existing glossary for this repo (previously at %s). Relink it?"):format(
      desc.relink.old_root
    )
    if vim.fn.confirm(msg, "&Yes\n&No", 1) == 1 then
      project.relink(desc.relink.id, desc.root)
      desc = project.resolve()
    end
  end
  if vim.tbl_contains(cmd.fargs, "-p") then
    local ga = vim.fn.confirm(
      "Add the recommended merge=union gitattribute for the glossary?",
      "&Yes\n&No",
      1
    ) == 1
    local ok, res = pcall(project.init_in_repo, nil, { gitattributes = ga })
    if not ok then
      vim.notify("gloss: " .. tostring(res), vim.log.levels.ERROR)
      return
    end
    if res.created then
      vim.notify(("gloss: created %s (%d entries migrated in)"):format(res.path, res.migrated))
      events.emit("GlossStoreChanged", {})
    else
      vim.notify("gloss: project is already in in-repo mode")
    end
    return
  end
  if desc.mode == "in_repo" then
    vim.notify("gloss: project is already in in-repo mode (" .. desc.path .. ")")
    return
  end
  local ok, res, created = pcall(project.register)
  if not ok then
    vim.notify("gloss: " .. tostring(res), vim.log.levels.ERROR)
    return
  end
  if created then
    vim.notify(("gloss: project registered, store at %s"):format(res.path))
    events.emit("GlossStoreChanged", {})
  else
    vim.notify(("gloss: project already registered (%s)"):format(res.path))
  end
end

handlers.highlight = function(cmd)
  local highlights = require("gloss.highlights")
  local action = cmd.fargs[2] or "toggle"
  if action == "on" then
    highlights.set(true)
  elseif action == "off" then
    highlights.set(false)
  elseif action == "toggle" then
    highlights.set(not highlights.active())
  else
    vim.notify("gloss: usage is :Gloss highlight on|off|toggle", vim.log.levels.ERROR)
    return
  end
  vim.notify("gloss: term highlighting " .. (highlights.active() and "on" or "off"))
end

handlers.doctor = function()
  require("gloss.doctor").run()
end

handlers.gc = function()
  local project = require("gloss.project")
  local stale = project.stale_entries()
  if #stale == 0 then
    vim.notify("gloss: the registry is clean")
    return
  end
  local chosen = {}
  for _, entry in ipairs(stale) do
    local msg = ("Retire the registry entry for missing root %s? (its DB is backed up first)"):format(
      entry.root
    )
    if vim.fn.confirm(msg, "&Yes\n&No", 2) == 1 then
      chosen[#chosen + 1] = entry.id
    end
  end
  local removed = project.gc(chosen)
  vim.notify(("gloss: retired %d registry entr%s"):format(removed, removed == 1 and "y" or "ies"))
end

handlers.export = function(cmd)
  local path = vim.fs.normalize(cmd.fargs[2] or "glossary.jsonl")
  if vim.uv.fs_stat(path) and vim.fn.confirm(("Overwrite %s?"):format(path), "&Yes\n&No", 2) ~= 1 then
    return
  end
  local ok, count = pcall(require("gloss.project").export_jsonl, path)
  if not ok then
    vim.notify("gloss: " .. tostring(count), vim.log.levels.ERROR)
    return
  end
  vim.notify(("gloss: exported %d entries to %s"):format(count, path))
end

handlers.import = function(cmd)
  if not cmd.fargs[2] then
    vim.notify("gloss: :Gloss import needs a path", vim.log.levels.ERROR)
    return
  end
  local ok, count, damaged = pcall(require("gloss.project").import_jsonl, vim.fs.normalize(cmd.fargs[2]))
  if not ok then
    vim.notify("gloss: " .. tostring(count), vim.log.levels.ERROR)
    return
  end
  require("gloss.events").emit("GlossStoreChanged", {})
  vim.notify(("gloss: imported %d entries"):format(count))
  if damaged > 0 then
    vim.notify(("gloss: %d damaged line(s) in the source were skipped"):format(damaged), vim.log.levels.WARN)
  end
end

handlers.help = function(cmd)
  local topic = cmd.fargs[2]
  if not topic or topic == "" then
    vim.cmd.help("gloss")
    return
  end
  for _, tag in ipairs({ topic, "gloss-" .. topic, ":Gloss-" .. topic, "gloss.setup." .. topic }) do
    if pcall(vim.cmd.help, tag) then
      return
    end
  end
  vim.notify(("gloss: no help for %q (see :h gloss)"):format(topic), vim.log.levels.WARN)
end

handlers.ai = function(cmd)
  local ai = require("gloss.ai")
  local root = (require("gloss.project").detect())
  local action = cmd.fargs[2] or "status"
  if action == "on" or action == "off" then
    ai.set_consent(root, action == "on")
    vim.notify(
      ("gloss: AI context sharing %s for %s"):format(action == "on" and "enabled" or "disabled", root)
    )
  elseif action == "status" then
    local provider = require("gloss.config").options.ai.provider
    vim.notify(table.concat({
      "gloss ai:",
      "  provider: " .. (provider and (provider.name or "unnamed") or "none configured"),
      ("  consent for %s: %s"):format(root, ai.consent(root) and "on" or "off"),
      "  ripgrep: " .. (vim.fn.executable("rg") == 1 and "found" or "missing (less context)"),
    }, "\n"))
  else
    vim.notify("gloss: usage is :Gloss ai on|off|status", vim.log.levels.ERROR)
  end
end

handlers.deinit = function()
  local project = require("gloss.project")
  if vim.fn.confirm("Convert the in-repo glossary back to an out-of-repo store?", "&Yes\n&No", 2) ~= 1 then
    return
  end
  local ok, res = pcall(project.deinit)
  if not ok then
    vim.notify("gloss: " .. tostring(res), vim.log.levels.ERROR)
    return
  end
  require("gloss.events").emit("GlossStoreChanged", {})
  vim.notify(
    ("gloss: imported %d entries to %s; remove the in-repo data yourself with: %s"):format(
      res.imported,
      res.path,
      res.remove_hint
    )
  )
end

---@param cmd table the nvim_create_user_command callback argument
function M.dispatch(cmd)
  local sub = cmd.fargs[1] or "lookup"
  if not vim.tbl_contains(SUBCOMMANDS, sub) then
    vim.notify(("gloss: unknown subcommand %q (see :h :Gloss)"):format(sub), vim.log.levels.ERROR)
    return
  end
  local handler = handlers[sub]
  if not handler then
    vim.notify(
      (":Gloss %s is designed but not built yet (see DESIGN.md for the build order)"):format(sub),
      vim.log.levels.WARN
    )
    return
  end
  handler(cmd)
end

local function term_candidates()
  local project = require("gloss.project")
  local terms, seen = {}, {}
  for _, scope in ipairs({ "project", "global" }) do
    local ok, handle = pcall(project.scope_store, scope)
    if ok and handle then
      for _, entry in ipairs(handle:list()) do
        if not seen[entry.term] then
          seen[entry.term] = true
          terms[#terms + 1] = entry.term
        end
      end
    end
  end
  table.sort(terms)
  return terms
end

local ARG_CANDIDATES = {
  edit = term_candidates,
  delete = term_candidates,
  lookup = term_candidates,
  search = function()
    return require("gloss.search").tag_candidates("all")
  end,
  list = function()
    return require("gloss.search").tag_candidates("project")
  end,
  init = function()
    return { "-p" }
  end,
  ai = function()
    return { "on", "off", "status" }
  end,
  highlight = function()
    return { "on", "off", "toggle" }
  end,
  export = function(arglead)
    return vim.fn.getcompletion(arglead, "file")
  end,
  import = function(arglead)
    return vim.fn.getcompletion(arglead, "file")
  end,
  help = function()
    return vim.fn.getcompletion("gloss", "help")
  end,
}

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  local after = cmdline:match("Gloss!?%s+(.*)$") or ""
  local before_lead = after:sub(1, #after - #arglead)
  local candidates
  if not before_lead:find("%S") then
    candidates = SUBCOMMANDS
  else
    local sub = before_lead:match("^%s*(%S+)")
    local fn = ARG_CANDIDATES[sub]
    candidates = fn and fn(arglead) or {}
  end
  return vim.tbl_filter(function(item)
    return vim.startswith(item, arglead)
  end, candidates)
end

--- The full subcommand list (the doc-drift test keeps the manual honest
--- against this).
---@return string[]
function M.subcommands()
  return vim.deepcopy(SUBCOMMANDS)
end

return M

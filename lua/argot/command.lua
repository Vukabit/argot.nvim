--- :Argot subcommand dispatch and completion. A subcommand that exists in
--- the list but has no handler responds honestly instead of failing
--- silently.

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
  "reset",
  "doctor",
  "help",
}

local handlers = {}

handlers.lookup = function(cmd)
  require("argot.lookup").run(cmd.fargs[2], { range = cmd.range and cmd.range > 0 or nil })
end

handlers.add = function(cmd)
  require("argot.lookup").add(cmd.fargs[2])
end

handlers.edit = function(cmd)
  require("argot.lookup").edit(cmd.fargs[2])
end

handlers.delete = function(cmd)
  require("argot.lookup").delete(cmd.fargs[2])
end

handlers.search = function(cmd)
  require("argot.search").run(table.concat(vim.list_slice(cmd.fargs, 2), " "))
end

handlers.list = function(cmd)
  require("argot.search").list(table.concat(vim.list_slice(cmd.fargs, 2), " "))
end

handlers.projects = function()
  require("argot.search").projects()
end

handlers.relink = function()
  local project = require("argot.project")
  local desc = project.resolve()
  if desc.mode == "in_repo" then
    vim.notify(
      "argot: in-repo projects need no relinking (identity is the checked-out .argot/)",
      vim.log.levels.INFO
    )
    return
  end
  if desc.relink then
    local msg = ("Relink this repo to its existing glossary (previously at %s)?"):format(desc.relink.old_root)
    if vim.fn.confirm(msg, "&Yes\n&No", 1) == 1 then
      project.relink(desc.relink.id, desc.root)
      require("argot.events").emit("ArgotStoreChanged", {})
      vim.notify("argot: relinked")
    end
    return
  end
  if desc.registry_id then
    vim.notify("argot: this project is already linked", vim.log.levels.INFO)
    return
  end
  local reg = project.load_registry()
  local ids = {}
  for id in pairs(reg.projects) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  if #ids == 0 then
    vim.notify("argot: the registry is empty; nothing to relink to", vim.log.levels.INFO)
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
    require("argot.events").emit("ArgotStoreChanged", {})
    vim.notify(("argot: relinked %s here"):format(reg.projects[id].root))
  end)
end

handlers.init = function(cmd)
  local project = require("argot.project")
  local events = require("argot.events")
  local desc = project.resolve()
  if desc.relink then
    local msg = ("argot: found an existing glossary for this repo (previously at %s). Relink it?"):format(
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
      vim.notify("argot: " .. tostring(res), vim.log.levels.ERROR)
      return
    end
    if res.created then
      vim.notify(("argot: created %s (%d entries migrated in)"):format(res.path, res.migrated))
      events.emit("ArgotStoreChanged", {})
    else
      vim.notify("argot: project is already in in-repo mode")
    end
    return
  end
  if desc.mode == "in_repo" then
    vim.notify("argot: project is already in in-repo mode (" .. desc.path .. ")")
    return
  end
  local ok, res, created = pcall(project.register)
  if not ok then
    vim.notify("argot: " .. tostring(res), vim.log.levels.ERROR)
    return
  end
  if created then
    vim.notify(("argot: project registered, store at %s"):format(res.path))
    events.emit("ArgotStoreChanged", {})
  else
    vim.notify(("argot: project already registered (%s)"):format(res.path))
  end
end

handlers.reset = function(cmd)
  local project = require("argot.project")
  local events = require("argot.events")
  local scope = cmd.fargs[2]
  if scope == "project" then
    local desc = project.resolve()
    if desc.mode == "in_repo" then
      vim.notify(
        "argot: in-repo glossaries belong to the repo; remove " .. desc.path .. " with git instead",
        vim.log.levels.WARN
      )
      return
    end
    if not desc.registry_id then
      vim.notify("argot: this project has no glossary to reset", vim.log.levels.INFO)
      return
    end
    if vim.fn.confirm("Retire this project's glossary? (its DB is backed up first)", "&Yes\n&No", 2) ~= 1 then
      return
    end
    local removed = project.gc({ desc.registry_id })
    events.emit("ArgotStoreChanged", {})
    vim.notify(removed == 1 and "argot: project glossary retired (backup kept)" or "argot: nothing retired")
  elseif scope == "global" then
    if vim.fn.confirm("Reset the GLOBAL dictionary? (it is moved into backups/)", "&Yes\n&No", 2) ~= 1 then
      return
    end
    local ok, res = pcall(project.reset_global)
    if not ok then
      vim.notify("argot: " .. tostring(res), vim.log.levels.ERROR)
      return
    end
    events.emit("ArgotStoreChanged", {})
    vim.notify(
      res.existed and ("argot: global dictionary moved to " .. res.backup)
        or "argot: no global dictionary yet"
    )
  elseif scope == "all" then
    local typed = vim.fn.input(
      "Type 'wipe' to move ALL argot data (global, every project, registry, AI consent) into backups/: "
    )
    if typed ~= "wipe" then
      vim.notify("argot: reset cancelled", vim.log.levels.INFO)
      return
    end
    local ok, res = pcall(project.reset_all)
    if not ok then
      vim.notify("argot: " .. tostring(res), vim.log.levels.ERROR)
      return
    end
    events.emit("ArgotStoreChanged", {})
    vim.notify(
      ("argot: clean slate; previous data archived at %s (in-repo glossaries untouched)"):format(res.dest)
    )
  else
    vim.notify("argot: usage is :Argot reset project|global|all", vim.log.levels.ERROR)
  end
end

handlers.highlight = function(cmd)
  local highlights = require("argot.highlights")
  local action = cmd.fargs[2] or "toggle"
  if action == "on" then
    highlights.set(true)
  elseif action == "off" then
    highlights.set(false)
  elseif action == "toggle" then
    highlights.set(not highlights.active())
  else
    vim.notify("argot: usage is :Argot highlight on|off|toggle", vim.log.levels.ERROR)
    return
  end
  vim.notify("argot: term highlighting " .. (highlights.active() and "on" or "off"))
end

handlers.doctor = function()
  require("argot.doctor").run()
end

handlers.gc = function()
  local project = require("argot.project")
  local stale = project.stale_entries()
  if #stale == 0 then
    vim.notify("argot: the registry is clean")
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
  vim.notify(("argot: retired %d registry entr%s"):format(removed, removed == 1 and "y" or "ies"))
end

handlers.export = function(cmd)
  -- join the tail so paths with spaces survive fargs splitting
  local arg = table.concat(vim.list_slice(cmd.fargs, 2), " ")
  local path = vim.fs.normalize(arg ~= "" and arg or "glossary.jsonl")
  if vim.uv.fs_stat(path) and vim.fn.confirm(("Overwrite %s?"):format(path), "&Yes\n&No", 2) ~= 1 then
    return
  end
  local ok, count = pcall(require("argot.project").export_jsonl, path)
  if not ok then
    vim.notify("argot: " .. tostring(count), vim.log.levels.ERROR)
    return
  end
  vim.notify(("argot: exported %d entries to %s"):format(count, path))
end

handlers.import = function(cmd)
  local arg = table.concat(vim.list_slice(cmd.fargs, 2), " ")
  if arg == "" then
    vim.notify("argot: :Argot import needs a path", vim.log.levels.ERROR)
    return
  end
  local ok, count, damaged = pcall(require("argot.project").import_jsonl, vim.fs.normalize(arg))
  if not ok then
    vim.notify("argot: " .. tostring(count), vim.log.levels.ERROR)
    return
  end
  require("argot.events").emit("ArgotStoreChanged", {})
  vim.notify(("argot: imported %d entries"):format(count))
  if damaged > 0 then
    vim.notify(("argot: %d damaged line(s) in the source were skipped"):format(damaged), vim.log.levels.WARN)
  end
end

handlers.help = function(cmd)
  local topic = cmd.fargs[2]
  if not topic or topic == "" then
    vim.cmd.help("argot")
    return
  end
  for _, tag in ipairs({ topic, "argot-" .. topic, ":Argot-" .. topic, "argot.setup." .. topic }) do
    if pcall(vim.cmd.help, tag) then
      return
    end
  end
  vim.notify(("argot: no help for %q (see :h argot)"):format(topic), vim.log.levels.WARN)
end

handlers.ai = function(cmd)
  local ai = require("argot.ai")
  local root = (require("argot.project").detect())
  local action = cmd.fargs[2] or "status"
  if action == "on" or action == "off" then
    ai.set_consent(root, action == "on")
    vim.notify(
      ("argot: AI context sharing %s for %s"):format(action == "on" and "enabled" or "disabled", root)
    )
  elseif action == "status" then
    local provider = require("argot.config").options.ai.provider
    vim.notify(table.concat({
      "argot ai:",
      "  provider: " .. (provider and (provider.name or "unnamed") or "none configured"),
      ("  consent for %s: %s"):format(root, ai.consent(root) and "on" or "off"),
      "  ripgrep: " .. (vim.fn.executable("rg") == 1 and "found" or "missing (less context)"),
    }, "\n"))
  else
    vim.notify("argot: usage is :Argot ai on|off|status", vim.log.levels.ERROR)
  end
end

handlers.deinit = function()
  local project = require("argot.project")
  if vim.fn.confirm("Convert the in-repo glossary back to an out-of-repo store?", "&Yes\n&No", 2) ~= 1 then
    return
  end
  local ok, res = pcall(project.deinit)
  if not ok then
    vim.notify("argot: " .. tostring(res), vim.log.levels.ERROR)
    return
  end
  require("argot.events").emit("ArgotStoreChanged", {})
  vim.notify(
    ("argot: imported %d entries to %s; remove the in-repo data yourself with: %s"):format(
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
    vim.notify(("argot: unknown subcommand %q (see :h :Argot)"):format(sub), vim.log.levels.ERROR)
    return
  end
  local handler = handlers[sub]
  if not handler then
    vim.notify(
      (":Argot %s is designed but not built yet (see DESIGN.md for the build order)"):format(sub),
      vim.log.levels.WARN
    )
    return
  end
  handler(cmd)
end

local function term_candidates()
  local project = require("argot.project")
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
    return require("argot.search").tag_candidates("all")
  end,
  list = function()
    return require("argot.search").tag_candidates("local")
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
  reset = function()
    return { "project", "global", "all" }
  end,
  export = function(arglead)
    return vim.fn.getcompletion(arglead, "file")
  end,
  import = function(arglead)
    return vim.fn.getcompletion(arglead, "file")
  end,
  help = function()
    return vim.fn.getcompletion("argot", "help")
  end,
}

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  local after = cmdline:match("Argot!?%s+(.*)$") or ""
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

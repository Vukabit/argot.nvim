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
  "doctor",
  "help",
}

-- implemented subcommands map to handler functions; everything else is
-- designed but not yet built (see DESIGN.md build order)
local handlers = {}

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
      (":Gloss %s is designed but not built yet; the storage layer landed first (see DESIGN.md)"):format(sub),
      vim.log.levels.WARN
    )
    return
  end
  handler(cmd)
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  -- only the subcommand position completes for now; per-subcommand argument
  -- completion (terms, project names, flags) arrives with the subcommands
  local after = cmdline:match("Gloss%s+(.*)$") or ""
  if after:find("%s") then
    return {}
  end
  return vim.tbl_filter(function(sub)
    return vim.startswith(sub, arglead)
  end, SUBCOMMANDS)
end

return M

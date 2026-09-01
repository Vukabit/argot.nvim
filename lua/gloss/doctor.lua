--- :Gloss doctor: the report of things silently wrong. Read-only; every
--- finding names the command that fixes it.

local M = {}

---@param opts? {startpath?: string}
---@return string[] lines, integer problems
function M.report(opts)
  local search = require("gloss.search")
  local project = require("gloss.project")
  local lines = { "gloss doctor", "" }
  local problems = 0

  local sources = search.sources(opts)
  for _, src in ipairs(sources) do
    src.store:list() -- refresh, so jsonl damage state is current
    for _, bad in ipairs(src.store.bad_lines or {}) do
      problems = problems + 1
      lines[#lines + 1] = ("[%s] damaged line %d (kept verbatim on writes): %s"):format(
        src.label,
        bad.lnum,
        bad.line:sub(1, 60)
      )
    end
    for _, term in ipairs(src.store.duplicates or {}) do
      problems = problems + 1
      lines[#lines + 1] = ("[%s] %q appears twice in one file (union merge?); edit the entries to reconcile"):format(
        src.label,
        term
      )
    end
  end

  local collected = search.collect(opts)

  local by_term = {}
  for _, item in ipairs(collected) do
    local key = item.entry.term:lower()
    by_term[key] = by_term[key] or {}
    table.insert(by_term[key], item)
  end
  -- the same term in several stores is informational, never a problem:
  -- a project definition shadowing the global one is intentional layering,
  -- and unrelated projects legitimately share vocabulary
  local overlap = {}
  local keys = vim.tbl_keys(by_term)
  table.sort(keys)
  for _, key in ipairs(keys) do
    local group = by_term[key]
    local labels, seen_labels = {}, {}
    for _, item in ipairs(group) do
      if not seen_labels[item.label] then
        seen_labels[item.label] = true
        labels[#labels + 1] = "[" .. item.label .. "]"
      end
    end
    if #labels > 1 then
      overlap[#overlap + 1] = ("%q is defined in %s (project shadows global on lookup; :Gloss search %s)"):format(
        group[1].entry.term,
        table.concat(labels, " "),
        group[1].entry.term
      )
    end
  end

  -- [[links]] pointing at terms no store defines
  local links = require("gloss.links")
  local lookup = require("gloss.lookup")
  local case_cfg = require("gloss.config").options.case
  local all_entries = vim.tbl_map(function(item)
    return item.entry
  end, collected)
  for _, item in ipairs(collected) do
    for _, target in ipairs(links.extract(item.entry.definition)) do
      if not lookup.policy_match(all_entries, target, case_cfg) then
        problems = problems + 1
        lines[#lines + 1] = ("[%s] %q links to [[%s]], which is not defined anywhere (:Gloss add %s)"):format(
          item.label,
          item.entry.term,
          target,
          target
        )
      end
    end
  end

  for _, stale in ipairs(project.stale_entries()) do
    problems = problems + 1
    lines[#lines + 1] = ("registry root no longer exists: %s (:Gloss gc)"):format(stale.root)
  end
  local desc = project.resolve(opts and opts.startpath)
  if desc.relink then
    problems = problems + 1
    lines[#lines + 1] = ("this repo matches a glossary registered at %s (:Gloss relink)"):format(
      desc.relink.old_root
    )
  end

  if problems == 0 then
    lines[#lines + 1] = "nothing wrong found"
  end
  if #overlap > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "overlap (informational, not a problem):"
    vim.list_extend(lines, overlap)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("%d finding(s) across %d store(s)"):format(problems, #sources)
  return lines, problems
end

function M.run()
  local lines = M.report()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local width = math.min(78, math.max(50, vim.o.columns - 8))
  local height = math.min(#lines + 1, math.max(8, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2 - 1)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    title = " gloss doctor ",
    title_pos = "center",
  })
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, false)
    end
  end, { buffer = buf, desc = "gloss: close" })
  return buf, win
end

return M

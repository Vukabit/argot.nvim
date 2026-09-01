--- Opt-in extmark highlighting of known terms, so glossed words are subtly
--- visible while reading. Honors the same case policy as lookup (a stored
--- "IT" never lights up the word "it"), refreshes on quiet moments rather
--- than per keystroke, and skips huge buffers.

local config = require("gloss.config")

local M = {}

local ns = vim.api.nvim_create_namespace("gloss_highlight")
local enabled = nil -- nil = follow config; :Gloss highlight overrides
local attached = false
local timers = {}

---@return boolean
function M.active()
  if enabled ~= nil then
    return enabled
  end
  return config.options.highlight.enabled == true
end

-- (word, ci) pairs for every term and alias reachable from this project
local function words()
  local project = require("gloss.project")
  local lookup = require("gloss.lookup")
  local out, seen = {}, {}
  for _, scope in ipairs(config.options.resolve) do
    local ok, handle = pcall(project.scope_store, scope)
    if ok and handle then
      local ok2, entries = pcall(handle.list, handle)
      if ok2 then
        for _, entry in ipairs(entries) do
          local ci = lookup.ci_allowed(entry, config.options.case)
          local candidates = { entry.term }
          vim.list_extend(candidates, entry.aliases or {})
          for _, text in ipairs(candidates) do
            local key = (ci and "i" or "s") .. text
            if text ~= "" and not seen[key] then
              seen[key] = true
              out[#out + 1] = { text = text, ci = ci }
            end
          end
        end
      end
    end
  end
  return out
end

local function is_word_char(char)
  return char:match("[%w_]") ~= nil
end

---@param buf integer?
function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= "" then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not M.active() then
    return
  end
  local cfg = config.options.highlight
  if vim.api.nvim_buf_line_count(buf) > (cfg.max_lines or 2000) then
    return
  end
  local terms = words()
  if #terms == 0 then
    return
  end
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local lower = line:lower()
    for _, term in ipairs(terms) do
      local hay = term.ci and lower or line
      local needle = term.ci and term.text:lower() or term.text
      local init = 1
      while true do
        local first, last = hay:find(needle, init, true)
        if not first then
          break
        end
        init = last + 1
        local before = first > 1 and line:sub(first - 1, first - 1) or ""
        local after = last < #line and line:sub(last + 1, last + 1) or ""
        if not is_word_char(before) and (after == "" or not is_word_char(after)) then
          vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, first - 1, {
            end_col = last,
            hl_group = cfg.hl_group or "GlossTerm",
          })
        end
      end
    end
  end
end

local function debounced_refresh(buf)
  local old = timers[buf]
  if old then
    old:stop()
    old:close()
  end
  local timer = vim.uv.new_timer()
  timers[buf] = timer
  timer:start(
    200,
    0,
    vim.schedule_wrap(function()
      if timers[buf] == timer then
        timers[buf] = nil
      end
      timer:stop()
      timer:close()
      M.refresh(buf)
    end)
  )
end

function M.attach()
  if attached then
    return
  end
  attached = true
  vim.api.nvim_set_hl(0, "GlossTerm", { default = true, underline = true })
  local group = vim.api.nvim_create_augroup("GlossHighlight", {})
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost", "InsertLeave" }, {
    group = group,
    callback = function(args)
      M.refresh(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("TextChanged", {
    group = group,
    callback = function(args)
      debounced_refresh(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "GlossEntryAdded", "GlossEntryChanged", "GlossEntryRemoved", "GlossStoreChanged" },
    callback = function()
      M.refresh()
    end,
  })
end

---@param on boolean
function M.set(on)
  enabled = on
  if on then
    M.attach()
    M.refresh()
  else
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      end
    end
  end
end

--- Extmark positions in a buffer, for tests and curiosity.
---@param buf integer
function M.marks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
end

return M

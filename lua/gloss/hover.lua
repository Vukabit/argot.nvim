--- hover.nvim integration: gloss as a pluggable hover provider, so the
--- K-style crowd gets definitions without any gloss keymap. Modern
--- hover.nvim loads providers as modules; users list
--- "gloss.providers.hover" in hover's config. register() covers older
--- hover.nvim versions that still expose a register function.

local M = {}

--- The word under a (line, col) position, cword-style.
---@param line string
---@param col integer 1-based
---@return string?
function M.word_at(line, col)
  if #line == 0 then
    return nil
  end
  col = math.min(math.max(col, 1), #line)
  local function is_word(i)
    return line:sub(i, i):match("[%w_]") ~= nil
  end
  if not is_word(col) then
    return nil
  end
  local first, last = col, col
  while first > 1 and is_word(first - 1) do
    first = first - 1
  end
  while last < #line and is_word(last + 1) do
    last = last + 1
  end
  return line:sub(first, last)
end

---@param opt? {bufnr?: integer, pos?: integer[]}
---@return GlossEntry?
function M._entry_at(opt)
  local word
  if type(opt) == "table" and opt.pos and opt.bufnr and vim.api.nvim_buf_is_valid(opt.bufnr) then
    local row = opt.pos[1]
    local line = (vim.api.nvim_buf_get_lines(opt.bufnr, row - 1, row, false))[1] or ""
    word = M.word_at(line, (opt.pos[2] or 0) + 1)
  end
  if not word or word == "" then
    -- <cword> reads the current window; never use it for some OTHER buffer
    if type(opt) == "table" and opt.bufnr and opt.bufnr ~= vim.api.nvim_get_current_buf() then
      return nil
    end
    word = vim.fn.expand("<cword>")
  end
  if not word or word == "" then
    return nil
  end
  -- never prompt (relink etc.) from inside a hover query
  return (require("gloss.lookup").find(word, { interactive = false }))
end

---@param entry GlossEntry
---@return string[]
function M._render(entry)
  local title = entry.term
  if entry.expansion then
    title = ("%s (%s)"):format(entry.term, entry.expansion)
  end
  local lines = { "# " .. title, "" }
  vim.list_extend(lines, vim.split(entry.definition or "", "\n", { plain = true }))
  if entry.tags and #entry.tags > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "#" .. table.concat(entry.tags, " #")
  end
  return lines
end

--- The provider table (Hover.Provider): enabled(bufnr, opts) and
--- execute(params, done) per hover.nvim's contract.
function M.provider()
  return {
    name = "Gloss",
    priority = 150,
    enabled = function(bufnr, opts)
      return M._entry_at({ bufnr = bufnr, pos = type(opts) == "table" and opts.pos or nil }) ~= nil
    end,
    execute = function(params, done)
      -- tolerate the ancient execute(done) calling convention
      if type(params) == "function" then
        params, done = nil, params
      end
      local entry = M._entry_at(type(params) == "table" and params or nil)
      if not entry then
        done(false)
        return
      end
      done({ lines = M._render(entry), filetype = "markdown" })
    end,
  }
end

--- Legacy path only: older hover.nvim versions exposed register().
--- Modern versions load providers as modules instead (see the module
--- comment in gloss/providers/hover.lua).
---@return boolean registered
function M.register()
  local ok, hover = pcall(require, "hover")
  if not ok or type(hover.register) ~= "function" then
    return false
  end
  return (pcall(hover.register, M.provider()))
end

return M

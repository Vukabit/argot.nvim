--- JSONL adapter: the git-friendly backend used for in-repo (`.gloss/`)
--- glossaries. One entry per line, sorted by term; the first line is a
--- version header. Writes are atomic (tmp file + rename) and reload before
--- merging, so concurrent editors lose nothing but a simultaneous edit of
--- the same term.

local store = require("gloss.store")

local M = {}

M.VERSION = 1

local Store = {}
Store.__index = Store

-- Fixed key order so identical data always serializes to identical bytes,
-- which keeps git diffs line-minimal.
local FIELD_ORDER = { "term", "expansion", "aliases", "tags", "source", "definition", "created_at", "updated_at" }
local KNOWN = {}
for _, key in ipairs(FIELD_ORDER) do
  KNOWN[key] = true
end

---@param entry GlossEntry
---@return string
local function encode_entry(entry)
  local parts = {}
  local function add(key, value)
    -- empty lists are omitted: vim.json can't tell {} from [], and the
    -- loader treats a missing list as empty anyway
    if value == nil or (type(value) == "table" and next(value) == nil) then
      return
    end
    parts[#parts + 1] = vim.json.encode(key) .. ":" .. vim.json.encode(value)
  end
  for _, key in ipairs(FIELD_ORDER) do
    add(key, entry[key])
  end
  local extra = {}
  for key in pairs(entry) do
    if not KNOWN[key] then
      extra[#extra + 1] = key
    end
  end
  table.sort(extra)
  for _, key in ipairs(extra) do
    add(key, entry[key])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

---@param path string
function M.open(path)
  local self = setmetatable({ path = path }, Store)
  self:_load()
  return self
end

function Store:_mtime()
  local stat = vim.uv.fs_stat(self.path)
  if not stat then
    return nil
  end
  return stat.mtime.sec * 1e9 + stat.mtime.nsec
end

function Store:_load()
  self.entries = {}
  self.bad_lines = {}
  self.duplicates = {}
  self.version = nil
  self.mtime = self:_mtime()
  if not self.mtime then
    return
  end
  for lnum, line in ipairs(vim.fn.readfile(self.path)) do
    if line ~= "" then
      local ok, obj = pcall(vim.json.decode, line)
      if not ok or type(obj) ~= "table" then
        self.bad_lines[#self.bad_lines + 1] = { lnum = lnum, line = line }
      elseif obj.gloss ~= nil then
        self.version = obj.gloss
      elseif type(obj.term) == "string" then
        if store.match(self.entries, obj.term) then
          self.duplicates[#self.duplicates + 1] = obj.term
        end
        obj.aliases = obj.aliases or {}
        obj.tags = obj.tags or {}
        self.entries[#self.entries + 1] = obj
      else
        self.bad_lines[#self.bad_lines + 1] = { lnum = lnum, line = line }
      end
    end
  end
end

function Store:_refresh()
  if self:_mtime() ~= self.mtime then
    self:_load()
  end
end

function Store:get(term, opts)
  self:_refresh()
  local _, entry = store.match(self.entries, term, opts)
  return entry and vim.deepcopy(entry) or nil
end

function Store:list()
  self:_refresh()
  return vim.deepcopy(self.entries)
end

function Store:upsert(entry)
  self:_refresh()
  entry = store.normalize(entry)
  entry.updated_at = store.now()
  local index, existing = store.match(self.entries, entry.term)
  if existing then
    entry.created_at = existing.created_at or entry.created_at
    self.entries[index] = entry
  else
    self.entries[#self.entries + 1] = entry
  end
  self:_write()
  return vim.deepcopy(entry)
end

function Store:delete(term)
  self:_refresh()
  local index = store.match(self.entries, term)
  if not index then
    return false
  end
  table.remove(self.entries, index)
  self:_write()
  return true
end

function Store:close() end

function Store:_write()
  table.sort(self.entries, function(a, b)
    local la, lb = a.term:lower(), b.term:lower()
    if la ~= lb then
      return la < lb
    end
    return a.term < b.term
  end)
  local lines = { vim.json.encode({ gloss = M.VERSION }) }
  for _, entry in ipairs(self.entries) do
    lines[#lines + 1] = encode_entry(entry)
  end
  -- damaged lines (bad merges, hand edits) are preserved verbatim rather
  -- than silently dropped; `:Gloss doctor` reports them
  for _, bad in ipairs(self.bad_lines) do
    lines[#lines + 1] = bad.line
  end
  local dir = vim.fs.dirname(self.path)
  if dir and dir ~= "" then
    vim.fn.mkdir(dir, "p")
  end
  local tmp = self.path .. ".tmp"
  if vim.fn.writefile(lines, tmp) ~= 0 then
    error(("gloss: failed writing %s"):format(tmp))
  end
  local ok, err = vim.uv.fs_rename(tmp, self.path)
  if not ok then
    vim.uv.fs_unlink(tmp)
    error(("gloss: failed replacing %s: %s"):format(self.path, err or "unknown error"))
  end
  self.mtime = self:_mtime()
end

return M

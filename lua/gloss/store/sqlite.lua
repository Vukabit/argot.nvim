--- SQLite adapter (kkharji/sqlite.lua over the system libsqlite3): the
--- default backend for the global dictionary and out-of-repo project stores.
--- WAL mode keeps concurrent nvim instances safe.

local store = require("gloss.store")

local M = {}

M.USER_VERSION = 1

local Store = {}
Store.__index = Store

-- Nullable-in-spirit columns use '' instead of NULL so every bind is a plain
-- string; this sidesteps per-driver NULL representation quirks entirely.
local SCHEMA = [[
CREATE TABLE IF NOT EXISTS entries (
  term       TEXT PRIMARY KEY,
  expansion  TEXT NOT NULL DEFAULT '',
  definition TEXT NOT NULL DEFAULT '',
  aliases    TEXT NOT NULL DEFAULT '[]',
  tags       TEXT NOT NULL DEFAULT '[]',
  source     TEXT NOT NULL DEFAULT 'user',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
]]

---@return boolean
function M.available()
  return (pcall(require, "sqlite.db"))
end

---@param path string
function M.open(path)
  local ok, sqlite = pcall(require, "sqlite.db")
  if not ok then
    error("gloss: the sqlite backend requires kkharji/sqlite.lua and libsqlite3")
  end
  if path ~= ":memory:" then
    local dir = vim.fs.dirname(path)
    if dir and dir ~= "" then
      vim.fn.mkdir(dir, "p")
    end
  end
  local self = setmetatable({ db = sqlite.new(path) }, Store)
  self.db:open()
  self.db:eval("PRAGMA journal_mode = WAL")
  self.db:eval(SCHEMA)
  local rows = self.db:eval("PRAGMA user_version")
  local version = type(rows) == "table" and rows[1] and rows[1].user_version or 0
  if version == 0 then
    self.db:eval("PRAGMA user_version = " .. M.USER_VERSION)
  end
  return self
end

local function to_entry(row)
  local expansion = row.expansion
  if expansion == "" or expansion == vim.NIL then
    expansion = nil
  end
  return {
    term = row.term,
    expansion = expansion,
    definition = row.definition,
    aliases = vim.json.decode(row.aliases or "[]"),
    tags = vim.json.decode(row.tags or "[]"),
    source = row.source,
    created_at = row.created_at,
    updated_at = row.updated_at,
  }
end

function Store:list()
  local rows = self.db:eval("SELECT * FROM entries ORDER BY term")
  if type(rows) ~= "table" then
    return {}
  end
  return vim.tbl_map(to_entry, rows)
end

function Store:get(term, opts)
  local _, entry = store.match(self:list(), term, opts)
  return entry
end

function Store:upsert(entry)
  entry = store.normalize(entry)
  entry.updated_at = store.now()
  -- created_at is deliberately absent from the UPDATE set, so the original
  -- insertion time survives edits
  self.db:eval(
    [[
INSERT INTO entries (term, expansion, definition, aliases, tags, source, created_at, updated_at)
VALUES (:term, :expansion, :definition, :aliases, :tags, :source, :created_at, :updated_at)
ON CONFLICT(term) DO UPDATE SET
  expansion  = excluded.expansion,
  definition = excluded.definition,
  aliases    = excluded.aliases,
  tags       = excluded.tags,
  source     = excluded.source,
  updated_at = excluded.updated_at
]],
    {
      term = entry.term,
      expansion = entry.expansion or "",
      definition = entry.definition,
      aliases = vim.json.encode(entry.aliases),
      tags = vim.json.encode(entry.tags),
      source = entry.source,
      created_at = entry.created_at,
      updated_at = entry.updated_at,
    }
  )
  return self:get(entry.term)
end

function Store:delete(term)
  local existing = self:get(term)
  if not existing then
    return false
  end
  self.db:eval("DELETE FROM entries WHERE term = :term", { term = existing.term })
  return true
end

function Store:close()
  self.db:close()
end

return M

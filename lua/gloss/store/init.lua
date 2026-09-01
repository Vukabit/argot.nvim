--- Storage adapter layer. Every backend exposes the same contract:
---
---   open(path) -> store
---   store:get(term, opts?)  -- opts.ci for case-insensitive; matches aliases too
---   store:list()
---   store:upsert(entry, opts?)  -- insert or update by term; bumps
---                                  updated_at unless opts.touch == false
---                                  (migrations and imports preserve history)
---   store:delete(term)      -- true if something was removed
---   store:close()
---
--- Fuzzy search, case policy, and the resolution pipeline live ABOVE this
--- layer; adapters only do exact (or lowercased) term/alias retrieval on
--- corpora small enough to scan.

local M = {}

---@class GlossEntry
---@field term string canonical form
---@field expansion? string acronym expansion
---@field definition string markdown body
---@field aliases string[]
---@field tags string[]
---@field source "user"|"ai"|"ai_edited"
---@field created_at string ISO 8601 UTC
---@field updated_at string ISO 8601 UTC

local BACKENDS = {
  jsonl = "gloss.store.jsonl",
  sqlite = "gloss.store.sqlite",
}

---@param backend "jsonl"|"sqlite"
---@param path string
function M.open(backend, path)
  local mod = BACKENDS[backend]
  if not mod then
    error(("gloss: unknown storage backend %q"):format(backend))
  end
  return require(mod).open(path)
end

---@return string
function M.now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ") --[[@as string]]
end

--- Fill defaults on a partial entry. Provided values win so imports and
--- migrations keep their history.
---@param entry table
---@return GlossEntry
function M.normalize(entry)
  if type(entry) ~= "table" or type(entry.term) ~= "string" or entry.term == "" then
    error("gloss: an entry requires a non-empty term")
  end
  local e = vim.deepcopy(entry)
  e.definition = e.definition or ""
  e.aliases = e.aliases or {}
  e.tags = e.tags or {}
  e.source = e.source or "user"
  e.created_at = e.created_at or M.now()
  e.updated_at = e.updated_at or M.now()
  return e
end

--- Shared matcher used by every adapter. Two passes with term precedence:
--- an entry's own term always beats another entry's alias, and identity
--- operations (upsert, rename cleanup) pass terms_only so an alias can
--- never masquerade as an entry's key.
---@param entries GlossEntry[]
---@param term string
---@param opts? {ci?: boolean, terms_only?: boolean}
---@return integer? index
---@return GlossEntry? entry
function M.match(entries, term, opts)
  local ci = opts and opts.ci
  local needle = ci and term:lower() or term
  local function norm(text)
    return ci and text:lower() or text
  end
  for i, entry in ipairs(entries) do
    if type(entry.term) == "string" and norm(entry.term) == needle then
      return i, entry
    end
  end
  if opts and opts.terms_only then
    return nil, nil
  end
  for i, entry in ipairs(entries) do
    for _, alias in ipairs(type(entry.aliases) == "table" and entry.aliases or {}) do
      if type(alias) == "string" and norm(alias) == needle then
        return i, entry
      end
    end
  end
  return nil, nil
end

--- Coerce an entry read from disk into the shapes the rest of the plugin
--- assumes. Repo JSONL is hand-edited and union-merged; JSON null decodes
--- to vim.NIL (userdata), and any field can carry the wrong type.
---@param entry table
---@return table
function M.sanitize(entry)
  local function str_or_nil(value)
    return type(value) == "string" and value or nil
  end
  local function str_list(value)
    if type(value) ~= "table" then
      return {}
    end
    local out = {}
    for _, item in ipairs(value) do
      if type(item) == "string" then
        out[#out + 1] = item
      end
    end
    return out
  end
  entry.term = str_or_nil(entry.term)
  entry.expansion = str_or_nil(entry.expansion)
  entry.definition = str_or_nil(entry.definition) or ""
  entry.source = str_or_nil(entry.source) or "user"
  entry.created_at = str_or_nil(entry.created_at)
  entry.updated_at = str_or_nil(entry.updated_at)
  entry.aliases = str_list(entry.aliases)
  entry.tags = str_list(entry.tags)
  if type(entry.case_sensitive) ~= "boolean" then
    entry.case_sensitive = nil
  end
  return entry
end

return M

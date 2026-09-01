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

--- Shared exact/alias matcher used by every adapter.
---@param entries GlossEntry[]
---@param term string
---@param opts? {ci?: boolean}
---@return integer? index
---@return GlossEntry? entry
function M.match(entries, term, opts)
  local ci = opts and opts.ci
  local needle = ci and term:lower() or term
  for i, entry in ipairs(entries) do
    local candidates = { entry.term }
    vim.list_extend(candidates, entry.aliases or {})
    for _, candidate in ipairs(candidates) do
      if (ci and candidate:lower() or candidate) == needle then
        return i, entry
      end
    end
  end
  return nil, nil
end

return M

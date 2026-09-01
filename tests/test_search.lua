local eq = MiniTest.expect.equality

local config = require("argot.config")
local jsonl = require("argot.store.jsonl")
local project = require("argot.project")
local search = require("argot.search")

local has_sqlite = pcall(require, "sqlite.db")

local tmpdir

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      config.setup({ data_dir = vim.fs.joinpath(tmpdir, "data") })
      project.drop_handles()
    end,
    post_case = function()
      project.drop_handles()
      config.setup({})
      vim.fn.delete(tmpdir, "rf")
    end,
  },
})

local function items()
  local list = {
    {
      term = "DLQ",
      expansion = "dead letter queue",
      tags = { "aws", "queue" },
      definition = "poison messages",
    },
    { term = "SQS", tags = { "aws" }, definition = "Simple Queue Service" },
    { term = "monorepo", tags = {}, definition = "one repo, many packages" },
    { term = "LSP", aliases = { "language server" }, tags = { "editor" }, definition = "d" },
  }
  local out = {}
  for _, entry in ipairs(list) do
    out[#out + 1] = { entry = entry, store = {}, label = "test", scope = "project" }
  end
  return out
end

local function terms(result)
  return vim.tbl_map(function(item)
    return item.entry.term
  end, result)
end

T["parse_query splits tags from fuzzy words"] = function()
  local q = search.parse_query("#aws que #Editor stuff")
  eq(q.tags, { "aws", "editor" })
  eq(q.needle, "que stuff")
end

T["empty query returns everything"] = function()
  eq(#search.filter(items(), ""), 4)
  eq(#search.filter(items(), nil), 4)
end

T["tag tokens filter exactly and case-insensitively"] = function()
  eq(terms(search.filter(items(), "#aws")), { "DLQ", "SQS" })
  eq(terms(search.filter(items(), "#AWS #queue")), { "DLQ" })
  eq(terms(search.filter(items(), "#nope")), {})
end

T["fuzzy matches terms, aliases, and expansions"] = function()
  eq(terms(search.filter(items(), "dlq"))[1], "DLQ")
  eq(terms(search.filter(items(), "mnrepo"))[1], "monorepo")
  -- via alias and expansion words
  local hit = terms(search.filter(items(), "language"))
  eq(vim.tbl_contains(hit, "LSP"), true)
end

T["definition substring hits are appended after fuzzy hits"] = function()
  local result = terms(search.filter(items(), "poison"))
  eq(vim.tbl_contains(result, "DLQ"), true)
end

T["tags and fuzzy combine"] = function()
  eq(terms(search.filter(items(), "#aws dlq")), { "DLQ" })
end

T["copy respects collision policy"] = function()
  local src = jsonl.open(vim.fs.joinpath(tmpdir, "a.jsonl"))
  local dst = jsonl.open(vim.fs.joinpath(tmpdir, "b.jsonl"))
  src:upsert({ term = "API", definition = "mine", created_at = "2020-01-01T00:00:00Z" })
  dst:upsert({ term = "API", definition = "theirs" })

  eq(search.copy(src:get("API"), dst), false)
  eq(dst:get("API").definition, "theirs")

  eq(search.copy(src:get("API"), dst, { on_collision = "keep_both" }), true)
  eq(dst:get("API (copy)").definition, "mine")

  local dst_created = dst:get("API").created_at
  eq(search.copy(src:get("API"), dst, { on_collision = "overwrite" }), true)
  eq(dst:get("API").definition, "mine")
  -- created_at is per-store history ("first entered this store") and
  -- survives an overwrite, per the adapter contract
  eq(dst:get("API").created_at, dst_created)
end

T["move copies then deletes from the source"] = function()
  local src = jsonl.open(vim.fs.joinpath(tmpdir, "a.jsonl"))
  local dst = jsonl.open(vim.fs.joinpath(tmpdir, "b.jsonl"))
  src:upsert({ term = "API", definition = "d" })

  eq(search.move(src:get("API"), src, dst), true)
  eq(src:get("API"), nil)
  eq(dst:get("API").definition, "d")

  -- a cancelled collision moves nothing
  src:upsert({ term = "API", definition = "again" })
  eq(search.move(src:get("API"), src, dst), false)
  eq(src:get("API").definition, "again")
end

T["local_sources covers the lookup context: project and global, never other projects"] = function()
  if not has_sqlite then
    MiniTest.skip("sqlite.lua not available")
  end
  local a = vim.fs.joinpath(tmpdir, "here")
  local b = vim.fs.joinpath(tmpdir, "elsewhere")
  vim.fn.mkdir(a, "p")
  vim.fn.mkdir(b, "p")
  project.store_for(project.register(a)):upsert({ term = "LOCAL", definition = "d" })
  project.store_for(project.register(b)):upsert({ term = "FOREIGN", definition = "d" })
  project.global_store():upsert({ term = "EVERYWHERE", tags = { "web" }, definition = "d" })

  local scopes = vim.tbl_map(function(src)
    return src.scope
  end, search.local_sources({ startpath = a }))
  table.sort(scopes)
  eq(scopes, { "global", "project" })

  -- shadowing: the project's copy of a term wins over global's, and
  -- global-only terms still appear
  project.global_store():upsert({ term = "LOCAL", definition = "the global copy" })
  local by_term = {}
  for _, item in ipairs(search.context_items({ startpath = a })) do
    by_term[item.entry.term] = item
  end
  eq(by_term.LOCAL.scope, "project")
  eq(by_term.LOCAL.entry.definition, "d")
  eq(by_term.EVERYWHERE.scope, "global")
  eq(by_term.FOREIGN, nil)
  -- a global tag completes for :Argot list (needs the cwd, so build the
  -- items the same way list does, from local_sources)
  local tags = {}
  for _, src in ipairs(search.local_sources({ startpath = a })) do
    for _, entry in ipairs(src.store:list()) do
      vim.list_extend(tags, entry.tags or {})
    end
  end
  eq(vim.tbl_contains(tags, "web"), true)
end

T["sources enumerates current project, global, and other projects"] = function()
  if not has_sqlite then
    MiniTest.skip("sqlite.lua not available")
  end
  local a = vim.fs.joinpath(tmpdir, "proj-a")
  local b = vim.fs.joinpath(tmpdir, "proj-b")
  vim.fn.mkdir(a, "p")
  vim.fn.mkdir(b, "p")
  project.store_for(project.register(a)):upsert({ term = "A1", definition = "d" })
  project.store_for(project.register(b)):upsert({ term = "B1", definition = "d" })

  local sources = search.sources({ startpath = a })
  local labels = vim.tbl_map(function(src)
    return src.label .. ":" .. src.scope
  end, sources)
  table.sort(labels)
  eq(labels, { "global:global", "proj-a:project", "proj-b:other" })

  local collected = terms(search.collect({ startpath = a }))
  table.sort(collected)
  eq(collected, { "A1", "B1" })
end

return T

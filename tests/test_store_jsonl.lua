local eq = MiniTest.expect.equality

local jsonl = require("argot.store.jsonl")

local tmpdir

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
    end,
    post_case = function()
      vim.fn.delete(tmpdir, "rf")
    end,
  },
})

local function path()
  return vim.fs.joinpath(tmpdir, "glossary.jsonl")
end

T["opening a missing file yields an empty store"] = function()
  local s = jsonl.open(path())
  eq(s:list(), {})
  eq(s:get("anything"), nil)
end

T["upsert/get/list roundtrip survives reopen"] = function()
  local s = jsonl.open(path())
  s:upsert({
    term = "DLQ",
    expansion = "dead letter queue",
    definition = "Queue that collects messages which could not be processed.",
    tags = { "aws" },
  })
  local entry = s:get("DLQ")
  eq(entry.expansion, "dead letter queue")
  eq(entry.tags, { "aws" })
  eq(entry.source, "user")
  eq(#s:list(), 1)

  local reopened = jsonl.open(path())
  eq(reopened:get("DLQ").definition, "Queue that collects messages which could not be processed.")
end

T["file has a version header and sorted, term-first lines"] = function()
  local s = jsonl.open(path())
  s:upsert({ term = "zebra", definition = "z" })
  s:upsert({ term = "Alpha", definition = "a" })
  local lines = vim.fn.readfile(path())
  eq(lines[1], '{"argot":1}')
  eq(vim.startswith(lines[2], '{"term":"Alpha"'), true)
  eq(vim.startswith(lines[3], '{"term":"zebra"'), true)
  eq(#lines, 3)
end

T["updating preserves created_at and does not duplicate"] = function()
  local s = jsonl.open(path())
  s:upsert({ term = "API", definition = "v1", created_at = "2020-01-01T00:00:00Z" })
  local updated = s:upsert({ term = "API", definition = "v2" })
  eq(updated.created_at, "2020-01-01T00:00:00Z")
  eq(s:get("API").definition, "v2")
  eq(#s:list(), 1)
end

T["case-insensitive get is opt-in; aliases match"] = function()
  local s = jsonl.open(path())
  s:upsert({ term = "API", aliases = { "apis" }, definition = "d" })
  eq(s:get("api"), nil)
  eq(s:get("api", { ci = true }).term, "API")
  eq(s:get("apis").term, "API")
end

T["delete removes by term or alias and reports"] = function()
  local s = jsonl.open(path())
  s:upsert({ term = "API", aliases = { "apis" }, definition = "d" })
  eq(s:delete("apis"), true)
  eq(s:delete("API"), false)
  eq(s:list(), {})
end

T["pre-rename gloss headers load fine and upgrade on write"] = function()
  vim.fn.writefile({ '{"gloss":1}', '{"term":"API","definition":"d"}' }, path())
  local s = jsonl.open(path())
  eq(s.version, 1)
  eq(#s.bad_lines, 0)
  eq(s:get("API").definition, "d")
  s:upsert({ term = "DLQ", definition = "d" })
  eq(vim.fn.readfile(path())[1], '{"argot":1}')
end

T["damaged lines are tolerated on load and preserved on write"] = function()
  vim.fn.writefile({
    '{"argot":1}',
    '{"term":"API","definition":"good"}',
    "{{{ definitely not json",
  }, path())
  local s = jsonl.open(path())
  eq(#s:list(), 1)
  eq(#s.bad_lines, 1)

  s:upsert({ term = "DLQ", definition = "d" })
  local lines = vim.fn.readfile(path())
  eq(vim.tbl_contains(lines, "{{{ definitely not json"), true)
  eq(#jsonl.open(path()):list(), 2)
end

T["duplicate terms (e.g. from a union merge) are surfaced"] = function()
  vim.fn.writefile({
    '{"argot":1}',
    '{"term":"DLQ","definition":"a"}',
    '{"term":"DLQ","definition":"b"}',
  }, path())
  local s = jsonl.open(path())
  eq(s.duplicates, { "DLQ" })
  eq(#s:list(), 2)
end

T["external file changes are picked up on next access"] = function()
  local s = jsonl.open(path())
  s:upsert({ term = "API", definition = "mine" })
  -- simulate a teammate's git pull rewriting the file
  vim.fn.writefile({ '{"argot":1}', '{"term":"API","definition":"theirs"}' }, path())
  eq(s:get("API").definition, "theirs")
end

T["no tmp file is left behind after writes"] = function()
  local s = jsonl.open(path())
  s:upsert({ term = "API", definition = "d" })
  eq(vim.uv.fs_stat(path() .. ".tmp"), nil)
end

return T

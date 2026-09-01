local eq = MiniTest.expect.equality

local has_sqlite = pcall(require, "sqlite.db")

local tmpdir

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      if not has_sqlite then
        MiniTest.skip("sqlite.lua not available")
      end
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
    end,
    post_case = function()
      if tmpdir then
        vim.fn.delete(tmpdir, "rf")
      end
    end,
  },
})

local function open()
  return require("gloss.store.sqlite").open(vim.fs.joinpath(tmpdir, "test.db"))
end

T["upsert/get/list/delete roundtrip"] = function()
  local s = open()
  s:upsert({
    term = "DLQ",
    expansion = "dead letter queue",
    definition = "d",
    tags = { "aws" },
    aliases = { "dlqs" },
  })
  local entry = s:get("DLQ")
  eq(entry.expansion, "dead letter queue")
  eq(entry.tags, { "aws" })
  eq(s:get("dlqs").term, "DLQ")
  eq(s:get("dlq"), nil)
  eq(s:get("dlq", { ci = true }).term, "DLQ")
  eq(#s:list(), 1)
  eq(s:delete("DLQ"), true)
  eq(s:delete("DLQ"), false)
  s:close()
end

T["entries without expansion come back with nil expansion"] = function()
  local s = open()
  s:upsert({ term = "monorepo", definition = "One repo, many packages." })
  eq(s:get("monorepo").expansion, nil)
  s:close()
end

T["persists across reopen and preserves created_at on update"] = function()
  local s = open()
  s:upsert({ term = "API", definition = "v1", created_at = "2020-01-01T00:00:00Z" })
  s:close()

  local reopened = open()
  reopened:upsert({ term = "API", definition = "v2" })
  local entry = reopened:get("API")
  eq(entry.definition, "v2")
  eq(entry.created_at, "2020-01-01T00:00:00Z")
  eq(#reopened:list(), 1)
  reopened:close()
end

T["list is sorted by term"] = function()
  local s = open()
  s:upsert({ term = "zebra", definition = "z" })
  s:upsert({ term = "alpha", definition = "a" })
  local terms = vim.tbl_map(function(e)
    return e.term
  end, s:list())
  eq(terms, { "alpha", "zebra" })
  s:close()
end

return T

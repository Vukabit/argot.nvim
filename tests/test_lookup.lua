local eq = MiniTest.expect.equality

local lookup = require("argot.lookup")

local T = MiniTest.new_set()

local CASE = { short_acronym_len = 3 }

local function entries()
  return {
    { term = "IT", definition = "d" },
    { term = "API", aliases = { "apis" }, definition = "d" },
    { term = "HTTP", definition = "d" },
    { term = "monorepo", definition = "d" },
    { term = "Foo", case_sensitive = true, definition = "d" },
    { term = "DB", case_sensitive = false, definition = "d" },
  }
end

T["exact matches always hit"] = function()
  eq(lookup.policy_match(entries(), "IT", CASE).term, "IT")
  eq(lookup.policy_match(entries(), "API", CASE).term, "API")
  eq(lookup.policy_match(entries(), "monorepo", CASE).term, "monorepo")
end

T["short uppercase acronyms never match case-insensitively"] = function()
  eq(lookup.policy_match(entries(), "it", CASE), nil)
  eq(lookup.policy_match(entries(), "api", CASE), nil)
end

T["longer terms match case-insensitively"] = function()
  eq(lookup.policy_match(entries(), "http", CASE).term, "HTTP")
  eq(lookup.policy_match(entries(), "Monorepo", CASE).term, "monorepo")
end

T["per-entry case_sensitive overrides in both directions"] = function()
  eq(lookup.policy_match(entries(), "foo", CASE), nil)
  eq(lookup.policy_match(entries(), "db", CASE).term, "DB")
end

T["aliases follow the owning entry's case policy"] = function()
  eq(lookup.policy_match(entries(), "apis", CASE).term, "API")
  eq(lookup.policy_match(entries(), "APIS", CASE), nil)
end

T["short_acronym_len is configurable"] = function()
  local loose = { short_acronym_len = 0 }
  eq(lookup.policy_match(entries(), "it", loose).term, "IT")
end

return T

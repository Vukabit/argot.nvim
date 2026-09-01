local eq = MiniTest.expect.equality

local defbuf = require("gloss.defbuf")
local jsonl = require("gloss.store.jsonl")

local tmpdir

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
    end,
    post_case = function()
      vim.fn.delete(tmpdir, "rf")
      -- close any float the case left open
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= "" then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end,
  },
})

T["serialize/parse round trip"] = function()
  local entry = {
    term = "DLQ",
    expansion = "dead letter queue",
    aliases = { "dlqs", "dead-letter queue" },
    tags = { "aws", "queue" },
    definition = "Queue that collects messages\nwhich could not be processed.",
  }
  local parsed, err = defbuf.parse(defbuf.serialize(entry))
  eq(err, nil)
  eq(parsed.term, entry.term)
  eq(parsed.expansion, entry.expansion)
  eq(parsed.aliases, entry.aliases)
  eq(parsed.tags, entry.tags)
  eq(parsed.definition, entry.definition)
end

T["template keys with empty values parse to empty fields"] = function()
  local parsed, err = defbuf.parse(defbuf.serialize({ term = "API", definition = "d" }))
  eq(err, nil)
  eq(parsed.expansion, nil)
  eq(parsed.aliases, {})
  eq(parsed.tags, {})
end

T["parse errors are specific"] = function()
  local _, err = defbuf.parse({ "term: X", "no colon here" })
  eq(err ~= nil and err:find("key: value") ~= nil, true)

  _, err = defbuf.parse({ "term: X", "bogus: y", "", "body" })
  eq(err ~= nil and err:find("unknown header") ~= nil, true)

  _, err = defbuf.parse({ "term: ", "", "body" })
  eq(err, "the 'term' header is required")
end

T["trailing whitespace is trimmed from the body"] = function()
  local parsed = defbuf.parse({ "term: X", "", "body", "", "  " })
  eq(parsed.definition, "body")
end

T["saving an open buffer persists to its store"] = function()
  local store = jsonl.open(vim.fs.joinpath(tmpdir, "g.jsonl"))
  store:upsert({ term = "DLQ", definition = "old", created_at = "2020-01-01T00:00:00Z" })
  local entry = store:get("DLQ")

  local buf = defbuf.open(entry, { store = store, scope = "project" })
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  lines[#lines] = "new definition"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd.write()

  eq(vim.bo[buf].modified, false)
  local saved = store:get("DLQ")
  eq(saved.definition, "new definition")
  eq(saved.created_at, "2020-01-01T00:00:00Z")
end

T["editing the term header renames the entry"] = function()
  local store = jsonl.open(vim.fs.joinpath(tmpdir, "g.jsonl"))
  store:upsert({ term = "DLQ", definition = "d" })

  local buf = defbuf.open(store:get("DLQ"), { store = store, scope = "project" })
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  lines[1] = "term: DLQv2"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd.write()

  eq(store:get("DLQ"), nil)
  eq(store:get("DLQv2").definition, "d")
end

T["a new entry asks for a scope and saves there"] = function()
  local store = jsonl.open(vim.fs.joinpath(tmpdir, "g.jsonl"))
  local orig_select, orig_scope = vim.ui.select, defbuf._scope_store
  local asked
  vim.ui.select = function(items, _, cb)
    asked = items
    cb("project")
  end
  defbuf._scope_store = function()
    return store
  end

  local buf = defbuf.open({ term = "FOO", definition = "" }, {})
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  lines[#lines] = "a fresh definition"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd.write()

  vim.ui.select, defbuf._scope_store = orig_select, orig_scope
  eq(asked, { "project", "global" })
  eq(store:get("FOO").definition, "a fresh definition")
  eq(store:get("FOO").source, "user")
  eq(vim.bo[buf].modified, false)
end

T["an invalid buffer refuses to save and stays modified"] = function()
  local store = jsonl.open(vim.fs.joinpath(tmpdir, "g.jsonl"))
  store:upsert({ term = "DLQ", definition = "d" })

  local buf = defbuf.open(store:get("DLQ"), { store = store, scope = "project" })
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "term: " })
  -- the ERROR-level notify surfaces as an error in headless autocmd context
  pcall(vim.cmd.write)

  eq(vim.bo[buf].modified, true)
  eq(store:get("DLQ").definition, "d")
end

return T

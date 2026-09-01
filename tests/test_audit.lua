-- Regression tests for the pre-release adversarial audit findings. Each
-- case pins a fixed bug; if one of these breaks, data loss is back.

local eq = MiniTest.expect.equality

local config = require("argot.config")
local defbuf = require("argot.defbuf")
local jsonl = require("argot.store.jsonl")
local project = require("argot.project")

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
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= "" then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
      project.drop_handles()
      config.setup({})
      vim.fn.delete(tmpdir, "rf")
    end,
  },
})

local function open_jsonl(name)
  return jsonl.open(vim.fs.joinpath(tmpdir, (name or "g") .. ".jsonl"))
end

T["BLOCKER 1: a new term colliding with another entry's alias coexists"] = function()
  local s = open_jsonl()
  s:upsert({ term = "HTTP", aliases = { "http2" }, definition = "the protocol" })
  s:upsert({ term = "http2", definition = "the newer protocol" })
  eq(#s:list(), 2)
  eq(s:get("HTTP").definition, "the protocol")
  -- an entry's own term beats another entry's alias
  eq(s:get("http2").definition, "the newer protocol")
end

T["BLOCKER 1 (sqlite): term precedence over foreign alias in get and delete"] = function()
  if not has_sqlite then
    MiniTest.skip("sqlite.lua not available")
  end
  local s = require("argot.store.sqlite").open(vim.fs.joinpath(tmpdir, "b1.db"))
  s:upsert({ term = "HTTP", aliases = { "http2" }, definition = "old" })
  s:upsert({ term = "http2", definition = "new" })
  eq(s:get("http2").definition, "new")
  eq(s:delete("http2"), true)
  eq(s:get("HTTP").definition, "old")
  -- with the shadowing term gone, the name resolves through HTTP's alias
  -- again: that is the designed fallback, not a leak
  eq(s:get("http2").term, "HTTP")
  s:close()
end

T["BLOCKER 2: renaming while keeping the old name as an alias keeps the save"] = function()
  local s = open_jsonl()
  s:upsert({ term = "FOO", definition = "original" })

  local buf = defbuf.open(s:get("FOO"), { store = s, scope = "project" })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "term: BAR",
    "expansion: ",
    "aliases: FOO",
    "tags: ",
    "",
    "renamed",
  })
  vim.cmd.write()

  eq(s:get("BAR").definition, "renamed")
  eq(s:get("BAR").aliases, { "FOO" })
  -- the old term is gone as a term but still resolves through the alias
  eq(select(2, require("argot.store").match(s:list(), "FOO", { terms_only = true })), nil)
  eq(s:get("FOO").term, "BAR")
end

T["hostile jsonl fields are sanitized instead of crashing the store"] = function()
  local path = vim.fs.joinpath(tmpdir, "hostile.jsonl")
  vim.fn.writefile({
    '{"argot":1}',
    '{"term":"STR","aliases":"notalist","tags":42}',
    '{"term":"NUL","expansion":null,"definition":null,"source":null}',
  }, path)
  local s = jsonl.open(path)
  eq(#s:list(), 2)
  eq(s:get("STR").aliases, {})
  eq(s:get("STR").tags, {})
  local nul = s:get("NUL")
  eq(nul.expansion, nil)
  eq(nul.definition, "")
  -- the fields that crashed defbuf/search/hover/links now serialize fine
  eq(type(table.concat(defbuf.serialize(nul), "\n")), "string")
  eq(require("argot.links").extract(nul.definition), {})
end

T["a corrupt registry refuses writes instead of resetting to empty"] = function()
  vim.fn.mkdir(config.data_dir(), "p")
  vim.fn.writefile({ "{not json" }, project.data_paths().registry)
  local ok, err = pcall(project.load_registry)
  eq(ok, false)
  eq(tostring(err):find("unreadable") ~= nil, true)
end

T["a line range without any prior visual selection falls back to cword"] = function()
  local lookup = require("argot.lookup")
  local ok, word = pcall(lookup.word, { range = true })
  eq(ok, true)
  eq(type(word), "string")
end

T["deinit into a same-remote sibling clone gets its own store"] = function()
  if not has_sqlite then
    MiniTest.skip("sqlite.lua not available")
  end
  local remote = "git@github.com:test/twins.git"
  local function mkgit(path)
    vim.fn.mkdir(path, "p")
    vim.system({ "git", "-C", path, "init", "-q" }):wait()
    vim.system({ "git", "-C", path, "remote", "add", "origin", remote }):wait()
    return path
  end
  local a = mkgit(vim.fs.joinpath(tmpdir, "clone-a"))
  local desc_a = project.register(a)

  local b = mkgit(vim.fs.joinpath(tmpdir, "clone-b"))
  local res = project.init_in_repo(b)
  jsonl.open(res.path):upsert({ term = "X", definition = "d" })
  local out = project.deinit(b)

  -- b's entries must not land in a's database
  eq(out.path ~= desc_a.path, true)
  eq(project.store_for(desc_a):get("X"), nil)
end

T["drop_handles leaves held handles usable; close_handles closes them"] = function()
  if not has_sqlite then
    MiniTest.skip("sqlite.lua not available")
  end
  local root = vim.fs.joinpath(tmpdir, "held")
  vim.fn.mkdir(root, "p")
  local handle = project.store_for(project.register(root))
  handle:upsert({ term = "A", definition = "d" })
  project.drop_handles()
  -- a definition float holding this handle can still save
  eq(handle:upsert({ term = "B", definition = "d" }).term, "B")
  project.close_handles()
end

T["resolve is cached until the registry changes"] = function()
  local root = vim.fs.joinpath(tmpdir, "cached")
  vim.fn.mkdir(root, "p")
  eq(project.resolve(root).mode, "unregistered")
  project.register(root)
  -- save_registry invalidated the cache: the fresh answer is registered
  eq(project.resolve(root).mode, "out_of_repo")
end

return T

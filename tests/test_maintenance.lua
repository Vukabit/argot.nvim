local eq = MiniTest.expect.equality

local config = require("gloss.config")
local doctor = require("gloss.doctor")
local jsonl = require("gloss.store.jsonl")
local project = require("gloss.project")

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

local function report_text(opts)
  local lines, problems = doctor.report(opts)
  return table.concat(lines, "\n"), problems
end

T["doctor is quiet on a healthy setup"] = function()
  local root = vim.fs.joinpath(tmpdir, "clean")
  vim.fn.mkdir(root, "p")
  project.init_in_repo(root)
  local text, problems = report_text({ startpath = root })
  eq(problems, 0)
  eq(text:find("nothing wrong found") ~= nil, true)
end

T["doctor reports damage, duplicates, cross-store terms, and stale roots"] = function()
  if not has_sqlite then
    MiniTest.skip("sqlite.lua not available")
  end
  local root = vim.fs.joinpath(tmpdir, "messy")
  vim.fn.mkdir(root, "p")
  local res = project.init_in_repo(root)
  vim.fn.writefile({
    '{"gloss":1}',
    '{"term":"DLQ","definition":"a"}',
    '{"term":"DLQ","definition":"b"}',
    "{{{ merge wreckage",
  }, res.path)
  project.global_store():upsert({ term = "dlq", definition = "global one" })

  -- a registered project whose root vanishes
  local ghost = vim.fs.joinpath(tmpdir, "ghost")
  vim.fn.mkdir(ghost, "p")
  project.register(ghost)
  vim.fn.delete(ghost, "rf")

  local text, problems = report_text({ startpath = root })
  eq(problems >= 4, true)
  eq(text:find("damaged line 4") ~= nil, true)
  eq(text:find("appears twice in one file") ~= nil, true)
  eq(text:find("is defined in") ~= nil, true)
  eq(text:find("registry root no longer exists") ~= nil, true)
end

T["gc retires only chosen stale entries and keeps a backup"] = function()
  if not has_sqlite then
    MiniTest.skip("sqlite.lua not available")
  end
  local ghost = vim.fs.joinpath(tmpdir, "ghost")
  vim.fn.mkdir(ghost, "p")
  local desc = project.register(ghost)
  project.store_for(desc):upsert({ term = "X", definition = "d" })
  project.drop_handles()
  vim.fn.delete(ghost, "rf")

  local stale = project.stale_entries()
  eq(#stale, 1)
  eq(project.gc({}), 0)
  eq(project.gc({ stale[1].id }), 1)
  eq(#project.stale_entries(), 0)
  eq(vim.uv.fs_stat(desc.path), nil)
  local backups = vim.fn.glob(vim.fs.joinpath(project.data_paths().backups, "*-gc-*.db"), false, true)
  eq(#backups, 1)
end

T["export and import round-trip a project glossary"] = function()
  local root = vim.fs.joinpath(tmpdir, "exp")
  vim.fn.mkdir(root, "p")
  local res = project.init_in_repo(root)
  jsonl.open(res.path):upsert({ term = "DLQ", definition = "d", created_at = "2020-01-01T00:00:00Z" })

  local out = vim.fs.joinpath(tmpdir, "snapshot.jsonl")
  eq(project.export_jsonl(out, root), 1)
  eq(vim.fn.readfile(out)[1], '{"gloss":1}')

  local other = vim.fs.joinpath(tmpdir, "imp")
  vim.fn.mkdir(other, "p")
  project.init_in_repo(other)
  local imported, damaged = project.import_jsonl(out, other)
  eq(imported, 1)
  eq(damaged, 0)
  local got = project.project_store({ startpath = other }):get("DLQ")
  eq(got.definition, "d")
  eq(got.created_at, "2020-01-01T00:00:00Z")
end

T["import skips damaged lines but reports them"] = function()
  local target = vim.fs.joinpath(tmpdir, "tgt")
  vim.fn.mkdir(target, "p")
  project.init_in_repo(target)
  local src = vim.fs.joinpath(tmpdir, "wonky.jsonl")
  vim.fn.writefile({ '{"gloss":1}', '{"term":"API","definition":"d"}', "not json at all" }, src)

  local imported, damaged = project.import_jsonl(src, target)
  eq(imported, 1)
  eq(damaged, 1)
end

T["export overwrites to an exact snapshot"] = function()
  local root = vim.fs.joinpath(tmpdir, "snap")
  vim.fn.mkdir(root, "p")
  local res = project.init_in_repo(root)
  jsonl.open(res.path):upsert({ term = "A", definition = "d" })

  local out = vim.fs.joinpath(tmpdir, "out.jsonl")
  vim.fn.writefile({ '{"gloss":1}', '{"term":"STALE","definition":"old"}' }, out)
  project.export_jsonl(out, root)
  local snapshot = jsonl.open(out)
  eq(snapshot:get("STALE"), nil)
  eq(snapshot:get("A").definition, "d")
end

return T

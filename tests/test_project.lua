local eq = MiniTest.expect.equality

local config = require("argot.config")
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
      project.drop_handles()
      config.setup({})
      vim.fn.delete(tmpdir, "rf")
    end,
  },
})

local function real(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local function mkgit(path, remote)
  vim.fn.mkdir(path, "p")
  vim.system({ "git", "-C", path, "init", "-q" }):wait()
  if remote then
    vim.system({ "git", "-C", path, "remote", "add", "origin", remote }):wait()
  end
  return path
end

T["normalize_remote unifies url forms"] = function()
  local want = "github.com/shawn/argot.nvim"
  eq(project.normalize_remote("git@github.com:shawn/argot.nvim.git"), want)
  eq(project.normalize_remote("https://github.com/shawn/argot.nvim"), want)
  eq(project.normalize_remote("ssh://git@github.com/shawn/argot.nvim.git"), want)
  eq(project.normalize_remote(""), nil)
  eq(project.normalize_remote(nil), nil)
end

T["detect finds the project_dir marker upward"] = function()
  local root = vim.fs.joinpath(tmpdir, "proj")
  vim.fn.mkdir(vim.fs.joinpath(root, ".argot"), "p")
  vim.fn.mkdir(vim.fs.joinpath(root, "src", "deep"), "p")
  local found, mode = project.detect(vim.fs.joinpath(root, "src", "deep"))
  eq(found, real(root))
  eq(mode, "in_repo")
end

T["detect falls back to the git root, then the start path"] = function()
  local repo = mkgit(vim.fs.joinpath(tmpdir, "repo"))
  vim.fn.mkdir(vim.fs.joinpath(repo, "src"), "p")
  local found, mode = project.detect(vim.fs.joinpath(repo, "src"))
  eq(found, real(repo))
  eq(mode, "out_of_repo")

  local plain = vim.fs.joinpath(tmpdir, "plain")
  vim.fn.mkdir(plain, "p")
  local found2, mode2 = project.detect(plain)
  eq(found2, real(plain))
  eq(mode2, "out_of_repo")
end

T["register then resolve by path; re-register is a no-op"] = function()
  local root = vim.fs.joinpath(tmpdir, "plain")
  vim.fn.mkdir(root, "p")
  local desc, created = project.register(root)
  eq(created, true)
  eq(desc.mode, "out_of_repo")
  eq(type(desc.registry_id), "string")

  local desc2, created2 = project.register(root)
  eq(created2, false)
  eq(desc2.registry_id, desc.registry_id)
  eq(project.resolve(root).registry_id, desc.registry_id)
end

T["a moved repo is found by remote and relinks"] = function()
  local remote = "git@github.com:test/moved.git"
  local a = mkgit(vim.fs.joinpath(tmpdir, "location-a"), remote)
  local desc = project.register(a)
  eq(desc.registry_id ~= nil, true)

  -- "move": same remote, different path
  local b = mkgit(vim.fs.joinpath(tmpdir, "location-b"), remote)
  local moved = project.resolve(b)
  eq(moved.relink ~= nil, true)
  eq(moved.relink.id, desc.registry_id)
  eq(moved.relink.old_root, real(a))

  project.relink(moved.relink.id, real(b))
  eq(project.resolve(b).registry_id, desc.registry_id)
end

T["init_in_repo creates the marker and a valid header file"] = function()
  local root = vim.fs.joinpath(tmpdir, "fresh")
  vim.fn.mkdir(root, "p")
  local res = project.init_in_repo(root)
  eq(res.created, true)
  eq(res.migrated, 0)
  eq(vim.fn.readfile(res.path)[1], '{"argot":1}')
  local _, mode = project.detect(root)
  eq(mode, "in_repo")
  -- idempotent
  eq(project.init_in_repo(root).created, false)
end

T["init_in_repo writes the merge=union gitattribute once"] = function()
  local root = vim.fs.joinpath(tmpdir, "ga")
  vim.fn.mkdir(root, "p")
  project.init_in_repo(root, { gitattributes = true })
  local ga = vim.fs.joinpath(root, ".gitattributes")
  eq(vim.fn.readfile(ga), { ".argot/glossary.jsonl merge=union" })
end

T["init_in_repo migrates the out-of-repo store, backs it up, retires it"] = function()
  if not has_sqlite then
    MiniTest.skip("sqlite.lua not available")
  end
  local root = vim.fs.joinpath(tmpdir, "migrate")
  vim.fn.mkdir(root, "p")
  local desc = project.register(root)
  local db = project.store_for(desc)
  db:upsert({ term = "DLQ", definition = "d", created_at = "2020-01-01T00:00:00Z" })

  local res = project.init_in_repo(root)
  eq(res.migrated, 1)
  local migrated = require("argot.store.jsonl").open(res.path):get("DLQ")
  eq(migrated.definition, "d")
  eq(migrated.created_at, "2020-01-01T00:00:00Z")
  -- registry entry retired, old db gone, backup kept
  eq(project.load_registry().projects[desc.registry_id], nil)
  eq(vim.uv.fs_stat(desc.path), nil)
  local backups = vim.fn.glob(vim.fs.joinpath(project.data_paths().backups, "*.db"), false, true)
  eq(#backups, 1)
end

T["deinit imports the jsonl into an out-of-repo store"] = function()
  if not has_sqlite then
    MiniTest.skip("sqlite.lua not available")
  end
  local root = vim.fs.joinpath(tmpdir, "back")
  vim.fn.mkdir(root, "p")
  local res = project.init_in_repo(root)
  require("argot.store.jsonl").open(res.path):upsert({ term = "API", definition = "d" })

  local out = project.deinit(root)
  eq(out.imported, 1)
  eq(require("argot.store.sqlite").open(out.path):get("API").definition, "d")
  eq(out.remove_hint:find("rm %-rf") ~= nil, true)
end

T["project_store returns nil for unregistered and pending-relink projects"] = function()
  local plain = vim.fs.joinpath(tmpdir, "nostore")
  vim.fn.mkdir(plain, "p")
  local handle, desc = project.project_store({ startpath = plain })
  eq(handle, nil)
  eq(desc.mode, "unregistered")

  local remote = "git@github.com:test/pending.git"
  local a = mkgit(vim.fs.joinpath(tmpdir, "pend-a"), remote)
  project.register(a)
  local b = mkgit(vim.fs.joinpath(tmpdir, "pend-b"), remote)
  local handle2, desc2 = project.project_store({ startpath = b })
  eq(handle2, nil)
  eq(desc2.relink ~= nil, true)
end

return T

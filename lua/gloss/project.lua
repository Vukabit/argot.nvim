--- Project identity and store resolution.
---
--- A project is identified by a registry entry (UUID-named DB), never by a
--- hash of its path: paths are locations, not identities. Lookup order is
--- exact root path, then normalized git remote (catches moves and re-clones,
--- relink is confirmed by the caller). Git worktrees resolve to the main
--- worktree via --git-common-dir, so all worktrees share one glossary.
--- Presence of the project_dir marker (default `.gloss/`) switches the
--- project into in-repo JSONL mode and bypasses the registry entirely.

local config = require("gloss.config")
local store = require("gloss.store")
local util = require("gloss.util")

local M = {}

-- open store handles, keyed by "backend:path"
local handles = {}

function M.drop_handles()
  for _, handle in pairs(handles) do
    pcall(handle.close, handle)
  end
  handles = {}
end

function M.data_paths()
  local dir = config.data_dir()
  return {
    dir = dir,
    registry = vim.fs.joinpath(dir, "projects.json"),
    projects = vim.fs.joinpath(dir, "projects"),
    backups = vim.fs.joinpath(dir, "backups"),
    global_db = vim.fs.joinpath(dir, "global.db"),
  }
end

local function git_out(root, ...)
  local ok, proc = pcall(vim.system, { "git", "-C", root, ... }, { text = true })
  if not ok then
    return nil
  end
  local res = proc:wait()
  if res.code ~= 0 then
    return nil
  end
  return vim.trim(res.stdout or "")
end

--- Normalize a git remote URL into a protocol-free identity:
--- git@github.com:foo/bar.git and https://github.com/foo/bar
--- both become github.com/foo/bar.
---@param url string?
---@return string?
function M.normalize_remote(url)
  if not url or url == "" then
    return nil
  end
  url = url:gsub("%.git/?$", "")
  url = url:gsub("^%a[%w+.-]*://", "")
  url = url:gsub("^[^@/]+@", "")
  -- ssh shorthand host:path (a port would also be rewritten; acceptable,
  -- identities only need to be consistent, not parseable)
  url = url:gsub(":", "/", 1)
  return url
end

---@param root string
---@return string?
function M.remote(root)
  return M.normalize_remote(git_out(root, "config", "--get", "remote.origin.url"))
end

local function walk_up(startpath, marker)
  local dir = vim.fs.normalize(startpath)
  while dir do
    if vim.uv.fs_stat(vim.fs.joinpath(dir, marker)) then
      return dir
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      return nil
    end
    dir = parent
  end
end

--- Find the project root and its mode.
---@param startpath string?
---@return string root
---@return "in_repo"|"out_of_repo" mode
function M.detect(startpath)
  startpath = startpath or assert(vim.uv.cwd())
  -- canonicalize: registry roots must compare stably, and git reports real
  -- paths (on macOS /var is a symlink to /private/var)
  startpath = vim.fs.normalize(vim.uv.fs_realpath(startpath) or startpath)
  local marker_root = walk_up(startpath, config.options.project_dir)
  if marker_root then
    return marker_root, "in_repo"
  end
  local git_root = walk_up(startpath, ".git")
  if git_root then
    local common = git_out(git_root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common and common ~= "" and vim.fs.basename(common) == ".git" then
      -- worktrees share the main worktree's identity
      return vim.fs.dirname(common), "out_of_repo"
    end
    return git_root, "out_of_repo"
  end
  return startpath, "out_of_repo"
end

function M.load_registry()
  local reg = util.read_json(M.data_paths().registry)
  if type(reg) ~= "table" or type(reg.projects) ~= "table" then
    reg = { version = 1, projects = {} }
  end
  return reg
end

function M.save_registry(reg)
  util.write_json(M.data_paths().registry, reg)
end

local function sorted_ids(reg)
  local ids = {}
  for id in pairs(reg.projects) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

---@return string? id, table? entry, "path"|"remote"|nil how
function M.find_entry(reg, root, remote_url)
  for _, id in ipairs(sorted_ids(reg)) do
    if reg.projects[id].root == root then
      return id, reg.projects[id], "path"
    end
  end
  if remote_url then
    for _, id in ipairs(sorted_ids(reg)) do
      if reg.projects[id].remote == remote_url then
        return id, reg.projects[id], "remote"
      end
    end
  end
  return nil, nil, nil
end

--- Resolve the project's store descriptor without prompting or creating
--- anything. `relink` is set when the registry knows this repo under a
--- different (moved) path; the caller decides whether to relink.
---@param startpath string?
---@return table desc { mode, root, backend?, path?, registry_id?, relink?, remote? }
function M.resolve(startpath)
  local root, mode = M.detect(startpath)
  if mode == "in_repo" then
    return {
      mode = "in_repo",
      root = root,
      backend = "jsonl",
      path = vim.fs.joinpath(root, config.options.project_dir, "glossary.jsonl"),
    }
  end
  local reg = M.load_registry()
  local remote_url = M.remote(root)
  local id, entry, how = M.find_entry(reg, root, remote_url)
  if id and how == "path" then
    return {
      mode = "out_of_repo",
      root = root,
      backend = "sqlite",
      registry_id = id,
      path = vim.fs.joinpath(M.data_paths().projects, id .. ".db"),
    }
  end
  if id and how == "remote" then
    return {
      mode = "out_of_repo",
      root = root,
      backend = "sqlite",
      relink = { id = id, old_root = entry.root },
      path = vim.fs.joinpath(M.data_paths().projects, id .. ".db"),
    }
  end
  return { mode = "unregistered", root = root, remote = remote_url }
end

--- Point a registry entry at a new root (repo moved or re-cloned).
function M.relink(id, new_root)
  local reg = M.load_registry()
  local entry = assert(reg.projects[id], "gloss: unknown project id")
  entry.root = new_root
  entry.remote = M.remote(new_root) or entry.remote
  M.save_registry(reg)
end

--- Create the registry entry for an out-of-repo project.
---@param startpath string?
---@return table desc, boolean created
function M.register(startpath)
  local root, mode = M.detect(startpath)
  if mode == "in_repo" then
    error("gloss: project is in in-repo mode; there is nothing to register")
  end
  local reg = M.load_registry()
  local remote_url = M.remote(root)
  local id, _, how = M.find_entry(reg, root, remote_url)
  if id and how == "path" then
    return M.resolve(startpath), false
  end
  -- a remote match without relink means the caller declined; register fresh
  id = util.uuid()
  reg.projects[id] = {
    root = root,
    remote = remote_url,
    created_at = store.now(),
  }
  M.save_registry(reg)
  vim.fn.mkdir(M.data_paths().projects, "p")
  return M.resolve(startpath), true
end

function M.store_for(desc)
  if not desc or not desc.path or not desc.backend then
    return nil
  end
  local key = desc.backend .. ":" .. desc.path
  if not handles[key] then
    handles[key] = store.open(desc.backend, desc.path)
  end
  return handles[key]
end

---@return table? store
function M.global_store()
  if not require("gloss.store.sqlite").available() then
    return nil
  end
  return M.store_for({ backend = "sqlite", path = M.data_paths().global_db })
end

--- The project store, or nil (unregistered, or a pending relink the user
--- declined / could not be asked about).
---@param opts? {startpath?: string, interactive?: boolean}
---@return table? store, table desc
function M.project_store(opts)
  opts = opts or {}
  local desc = M.resolve(opts.startpath)
  if desc.relink then
    if not opts.interactive then
      return nil, desc
    end
    local msg = ("gloss: found an existing glossary for this repo (previously at %s). Relink it?"):format(
      desc.relink.old_root
    )
    if vim.fn.confirm(msg, "&Yes\n&No", 1) ~= 1 then
      return nil, desc
    end
    M.relink(desc.relink.id, desc.root)
    desc = M.resolve(opts.startpath)
  end
  if desc.mode == "unregistered" then
    return nil, desc
  end
  local ok, handle = pcall(M.store_for, desc)
  if not ok then
    return nil, desc
  end
  return handle, desc
end

---@param scope "project"|"global"
---@param opts? table passed through to project_store
---@return table? store
function M.scope_store(scope, opts)
  if scope == "global" then
    return M.global_store()
  end
  if scope == "project" then
    return (M.project_store(opts))
  end
end

local function ensure_jsonl_file(path)
  if vim.fn.filereadable(path) ~= 1 then
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({ ('{"gloss":%d}'):format(require("gloss.store.jsonl").VERSION) }, path)
  end
end

--- Switch the project into in-repo mode: create project_dir, fold any
--- registered out-of-repo entries in, back up and retire the old DB.
---@param startpath string?
---@param opts? {gitattributes?: boolean}
---@return table { root, path?, created, migrated }
function M.init_in_repo(startpath, opts)
  opts = opts or {}
  local root, mode = M.detect(startpath)
  if mode == "in_repo" then
    return { root = root, created = false, migrated = 0 }
  end
  local old_store, old_desc = M.project_store({ startpath = startpath })
  local entries = old_store and old_store:list() or {}

  local path = vim.fs.joinpath(root, config.options.project_dir, "glossary.jsonl")
  ensure_jsonl_file(path)
  local new_store = store.open("jsonl", path)
  for _, entry in ipairs(entries) do
    new_store:upsert(entry, { touch = false })
  end

  if old_store and old_desc.registry_id then
    old_store:close()
    vim.fn.mkdir(M.data_paths().backups, "p")
    local backup = vim.fs.joinpath(
      M.data_paths().backups,
      ("%s-%s.db"):format(old_desc.registry_id, os.date("!%Y%m%d%H%M%S"))
    )
    vim.uv.fs_copyfile(old_desc.path, backup)
    for _, suffix in ipairs({ "", "-wal", "-shm" }) do
      vim.uv.fs_unlink(old_desc.path .. suffix)
    end
    local reg = M.load_registry()
    reg.projects[old_desc.registry_id] = nil
    M.save_registry(reg)
  end

  if opts.gitattributes then
    local ga = vim.fs.joinpath(root, ".gitattributes")
    local line = config.options.project_dir .. "/glossary.jsonl merge=union"
    local lines = vim.fn.filereadable(ga) == 1 and vim.fn.readfile(ga) or {}
    if not vim.tbl_contains(lines, line) then
      lines[#lines + 1] = line
      vim.fn.writefile(lines, ga)
    end
  end

  M.drop_handles()
  return { root = root, path = path, created = true, migrated = #entries }
end

--- Reverse of init_in_repo: import the JSONL into an out-of-repo store.
--- Never deletes anything inside the repo; returns the command instead.
---@param startpath string?
---@return table { imported, path, remove_hint }
function M.deinit(startpath)
  local root, mode = M.detect(startpath)
  if mode ~= "in_repo" then
    error("gloss: project is not in in-repo mode")
  end
  local dir = vim.fs.joinpath(root, config.options.project_dir)
  local entries = store.open("jsonl", vim.fs.joinpath(dir, "glossary.jsonl")):list()

  local reg = M.load_registry()
  local remote_url = M.remote(root)
  local id = (M.find_entry(reg, root, remote_url))
  if not id then
    id = util.uuid()
    reg.projects[id] = { root = root, remote = remote_url, created_at = store.now() }
    M.save_registry(reg)
  end
  vim.fn.mkdir(M.data_paths().projects, "p")
  local path = vim.fs.joinpath(M.data_paths().projects, id .. ".db")
  local dst = store.open("sqlite", path)
  for _, entry in ipairs(entries) do
    dst:upsert(entry, { touch = false })
  end

  M.drop_handles()
  return { imported = #entries, path = path, remove_hint = "rm -rf " .. dir }
end

return M

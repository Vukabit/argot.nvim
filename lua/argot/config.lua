--- Configuration: defaults live here, setup() is optional, and list-valued
--- options replace rather than merge (so `resolve = { "project" }` really
--- does drop the global fallback).

local M = {}

-- options that are lists: a user-provided value replaces the default outright
local LIST_OPTIONS = { "resolve", "on_miss" }

local defaults = {
  -- directory name whose presence at the project root switches the project
  -- into in-repo (JSONL) mode
  project_dir = ".argot",
  -- lookup resolution chain, then the fallback chain on a miss
  resolve = { "project", "global" },
  on_miss = { "prompt" },
  -- false (nothing installed) | true (defaults under <leader>g) | table:
  --   { prefix?, lookup?, add?, search?, list?, projects? } where each action
  --   accepts a lhs string or false to disable that one map
  keymaps = false,
  case = {
    -- uppercase terms at or under this length match case-sensitively, so a
    -- stored "IT" never fires on the word "it"
    short_acronym_len = 3,
  },
  ai = {
    -- a ArgotProvider table; nil disables the AI miss handler entirely
    provider = nil,
    -- how much codebase context the request bundle carries
    context = {
      lines = 8, -- lines around the cursor
      usages = 20, -- capped project-wide ripgrep hits
    },
  },
  highlight = {
    -- opt-in: mark known terms in normal buffers with extmarks
    enabled = false,
    hl_group = "ArgotTerm",
    -- buffers longer than this are skipped
    max_lines = 2000,
  },
  -- override where global.db, the registry, and project DBs live
  -- (default: stdpath("data")/argot)
  data_dir = nil,
}

M.options = vim.deepcopy(defaults)

---@param opts table?
function M.setup(opts)
  opts = opts or {}
  vim.validate("opts", opts, "table")
  vim.validate("project_dir", opts.project_dir, "string", true)
  vim.validate("resolve", opts.resolve, "table", true)
  vim.validate("on_miss", opts.on_miss, "table", true)
  vim.validate("keymaps", opts.keymaps, { "boolean", "table" }, true)
  vim.validate("case", opts.case, "table", true)
  vim.validate("ai", opts.ai, "table", true)
  vim.validate("highlight", opts.highlight, "table", true)
  vim.validate("data_dir", opts.data_dir, "string", true)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  for _, key in ipairs(LIST_OPTIONS) do
    if opts[key] ~= nil then
      M.options[key] = vim.deepcopy(opts[key])
    end
  end
  return M.options
end

---@return string
function M.data_dir()
  if M.options.data_dir then
    return M.options.data_dir
  end
  local dir = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "argot")
  if not vim.uv.fs_stat(dir) then
    -- one-time migration from the pre-rename location (the plugin
    -- launched as gloss.nvim); registry contents are path-keyed, so a
    -- directory rename carries everything
    local legacy = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "gloss")
    if vim.uv.fs_stat(legacy) then
      vim.uv.fs_rename(legacy, dir)
    end
  end
  return dir
end

return M

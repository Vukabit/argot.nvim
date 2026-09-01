local eq = MiniTest.expect.equality

local config = require("argot.config")
local highlights = require("argot.highlights")
local jsonl = require("argot.store.jsonl")
local project = require("argot.project")
local statusline = require("argot.statusline")

local tmpdir, old_cwd

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      old_cwd = vim.uv.cwd()
      config.setup({ data_dir = vim.fs.joinpath(tmpdir, "data") })
      project.drop_handles()
    end,
    post_case = function()
      highlights.set(false)
      vim.cmd.cd(old_cwd)
      project.drop_handles()
      config.setup({})
      vim.fn.delete(tmpdir, "rf")
    end,
  },
})

local function make_project(entries)
  local root = vim.fs.joinpath(tmpdir, "proj")
  vim.fn.mkdir(root, "p")
  local res = project.init_in_repo(root)
  local store = jsonl.open(res.path)
  for _, entry in ipairs(entries) do
    store:upsert(entry)
  end
  vim.cmd.cd(root)
  return root, store
end

T["statusline shows the project count and tracks events"] = function()
  local _, store = make_project({ { term = "DLQ", definition = "d" } })
  eq(statusline.component(), "argot:1")
  -- cached until an event invalidates
  store:upsert({ term = "API", definition = "d" })
  eq(statusline.component(), "argot:1")
  require("argot.events").emit("ArgotEntryAdded", { term = "API", scope = "project" })
  eq(statusline.component(), "argot:2")
end

T["statusline is empty without a project glossary"] = function()
  vim.cmd.cd(tmpdir)
  require("argot.events").emit("ArgotStoreChanged", {})
  eq(statusline.component(), "")
end

T["highlighting marks known terms, honoring the case policy"] = function()
  make_project({
    { term = "DLQ", definition = "d" },
    { term = "monorepo", definition = "d" },
  })
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(tmpdir, "proj", "code.txt"))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "push(DLQ)", -- exact hit
    "the dlq here", -- short uppercase acronym: no ci match
    "our MONOREPO setup", -- long term: ci match
    "xmonorepox", -- no word boundary
  })
  vim.api.nvim_set_current_buf(buf)

  highlights.set(true)
  local marks = highlights.marks(buf)
  local rows = vim.tbl_map(function(mark)
    return mark[2]
  end, marks)
  table.sort(rows)
  eq(rows, { 0, 2 })

  highlights.set(false)
  eq(highlights.marks(buf), {})
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["highlighting skips oversized and special buffers"] = function()
  make_project({ { term = "DLQ", definition = "d" } })
  config.setup({ data_dir = vim.fs.joinpath(tmpdir, "data"), highlight = { max_lines = 2 } })
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "DLQ", "DLQ", "DLQ" })
  vim.api.nvim_set_current_buf(buf)
  highlights.set(true)
  eq(highlights.marks(buf), {})
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["telescope entries carry display, ordinal, and the item"] = function()
  make_project({
    { term = "DLQ", expansion = "dead letter queue", tags = { "aws" }, definition = "d" },
  })
  local entries = require("argot.telescope").entries("")
  eq(#entries, 1)
  eq(entries[1].value.entry.term, "DLQ")
  eq(entries[1].display:find("dead letter queue") ~= nil, true)
  eq(entries[1].ordinal:find("#aws") ~= nil, true)
  eq(entries[1].ordinal:find("proj") ~= nil, true)
  -- the query pre-filter uses the search grammar
  eq(#require("argot.telescope").entries("#nope"), 0)
end

T["the telescope extension registers"] = function()
  if not pcall(require, "telescope") then
    MiniTest.skip("telescope.nvim not available")
  end
  require("telescope").load_extension("argot")
  eq(type(require("telescope").extensions.argot.argot), "function")
end

return T

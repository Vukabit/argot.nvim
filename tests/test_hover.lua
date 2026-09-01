local eq = MiniTest.expect.equality

local config = require("gloss.config")
local hover = require("gloss.hover")
local project = require("gloss.project")

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

T["word_at finds cword-style words"] = function()
  eq(hover.word_at("local dlq = DLQ.new()", 13), "DLQ")
  eq(hover.word_at("local dlq = DLQ.new()", 16), nil) -- on the dot
  eq(hover.word_at("x", 1), "x")
  eq(hover.word_at("", 1), nil)
  eq(hover.word_at("  spaced  ", 1), nil)
  eq(hover.word_at("snake_case here", 3), "snake_case")
end

T["the provider finds entries and renders markdown"] = function()
  local root = vim.fs.joinpath(tmpdir, "proj")
  vim.fn.mkdir(root, "p")
  local res = project.init_in_repo(root)
  require("gloss.store.jsonl").open(res.path):upsert({
    term = "DLQ",
    expansion = "dead letter queue",
    tags = { "aws" },
    definition = "Queue for poison messages.",
  })

  local old_cwd = vim.uv.cwd()
  vim.cmd.cd(root)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "push(DLQ, msg)" })

  local provider = hover.provider()
  eq(provider.enabled(buf, { pos = { 1, 5 } }), true)
  eq(provider.enabled(buf, { pos = { 1, 0 } }), false) -- on "push"

  local result
  provider.execute({ bufnr = buf, pos = { 1, 5 } }, function(res_)
    result = res_
  end)
  eq(result.filetype, "markdown")
  eq(result.lines[1], "# DLQ (dead letter queue)")
  eq(vim.tbl_contains(result.lines, "Queue for poison messages."), true)
  eq(result.lines[#result.lines], "#aws")

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.cmd.cd(old_cwd)
end

T["the provider module satisfies hover.nvim's Hover.Provider contract"] = function()
  package.loaded["gloss.providers.hover"] = nil
  local provider = require("gloss.providers.hover")
  eq(type(provider), "table")
  eq(provider.name, "Gloss")
  eq(type(provider.execute), "function")
  eq(type(provider.enabled), "function")
  eq(type(provider.priority), "number")
end

T["modern hover.nvim accepts the provider module in its config"] = function()
  if not pcall(require, "hover") then
    MiniTest.skip("hover.nvim not available")
  end
  local ok, err = pcall(function()
    require("hover").config({
      providers = { "gloss.providers.hover" },
    })
  end)
  eq(ok, true, err)
end

return T

local eq = MiniTest.expect.equality

-- reset via setup({}) rather than reloading the module: a reload would fork
-- a second config instance and desync every module that captured the first
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      require("argot.config").setup({})
    end,
  },
})

T["defaults are usable without setup()"] = function()
  local config = require("argot.config")
  eq(config.options.project_dir, ".argot")
  eq(config.options.resolve, { "project", "global" })
  eq(config.options.on_miss, { "prompt" })
  eq(config.options.keymaps, false)
  eq(config.options.case.short_acronym_len, 3)
end

T["setup() deep-merges nested options over defaults"] = function()
  local config = require("argot.config")
  config.setup({ case = { short_acronym_len = 4 } })
  eq(config.options.case.short_acronym_len, 4)
  eq(config.options.project_dir, ".argot")
end

T["list options replace instead of index-merging"] = function()
  local config = require("argot.config")
  config.setup({ resolve = { "project" } })
  eq(config.options.resolve, { "project" })
end

T["setup() twice starts from defaults each time"] = function()
  local config = require("argot.config")
  config.setup({ project_dir = ".jargon" })
  config.setup({})
  eq(config.options.project_dir, ".argot")
end

T["invalid option types error"] = function()
  local config = require("argot.config")
  MiniTest.expect.error(function()
    config.setup({ resolve = "project" })
  end)
  MiniTest.expect.error(function()
    config.setup({ keymaps = "yes" })
  end)
end

T["keymaps accepts boolean or per-action table"] = function()
  local config = require("argot.config")
  config.setup({ keymaps = true })
  eq(config.options.keymaps, true)
  config.setup({ keymaps = { prefix = "<leader>x", add = false } })
  eq(config.options.keymaps.prefix, "<leader>x")
  eq(config.options.keymaps.add, false)
end

return T

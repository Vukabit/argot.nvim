-- The doc-drift guard: the manual must stay honest against the code.
-- Every subcommand, <Plug> mapping, and setup key needs its help tag, and
-- every :Argot-* tag in the manual must name a real subcommand.

local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2))))

local function doc_text()
  return table.concat(vim.fn.readfile(vim.fs.joinpath(root, "doc", "argot.txt")), "\n")
end

T["every subcommand has a help tag"] = function()
  local doc = doc_text()
  local missing = {}
  for _, sub in ipairs(require("argot.command").subcommands()) do
    if not doc:find(("*:Argot-%s*"):format(sub), 1, true) then
      missing[#missing + 1] = sub
    end
  end
  eq(missing, {})
end

T["every :Argot-* tag names a real subcommand"] = function()
  local subs = require("argot.command").subcommands()
  local bogus = {}
  for tag in doc_text():gmatch("%*:Argot%-(%w+)%*") do
    if not vim.tbl_contains(subs, tag) then
      bogus[#bogus + 1] = tag
    end
  end
  eq(bogus, {})
end

T["every <Plug> mapping is documented"] = function()
  local plugin_src = table.concat(vim.fn.readfile(vim.fs.joinpath(root, "plugin", "argot.lua")), "\n")
  local doc = doc_text()
  local missing = {}
  for plug in plugin_src:gmatch("(<Plug>%(Argot%w+%))") do
    if not doc:find(plug, 1, true) then
      missing[#missing + 1] = plug
    end
  end
  eq(missing, {})
end

T["every setup key has a config tag"] = function()
  require("argot.config").setup({})
  local options = require("argot.config").options
  local doc = doc_text()
  local missing = {}
  for key in pairs(options) do
    if not doc:find(("*argot.setup.%s*"):format(key), 1, true) then
      missing[#missing + 1] = key
    end
  end
  table.sort(missing)
  eq(missing, {})
end

return T

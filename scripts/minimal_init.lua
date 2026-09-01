-- Minimal init for tests and issue reproduction:
--   nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"
-- Dependencies are cloned into .deps/ by `make deps`.

local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2))))
vim.opt.runtimepath:prepend(root)
for _, dep in ipairs({ "mini.nvim", "sqlite.lua", "hover.nvim", "plenary.nvim", "telescope.nvim" }) do
  vim.opt.runtimepath:prepend(vim.fs.joinpath(root, ".deps", dep))
end

require("mini.test").setup()

-- Startup surface: one user command and the <Plug> contract, zero requires.
-- Everything loads on first use.

if vim.g.loaded_argot then
  return
end
vim.g.loaded_argot = 1

vim.api.nvim_create_user_command("Argot", function(cmd)
  require("argot.command").dispatch(cmd)
end, {
  nargs = "*",
  range = true,
  desc = "Project glossary",
  complete = function(arglead, cmdline, _)
    return require("argot.command").complete(arglead, cmdline)
  end,
})

vim.keymap.set({ "n", "x" }, "<Plug>(ArgotLookup)", function()
  require("argot.lookup").run()
end, { desc = "argot: lookup" })

vim.keymap.set("n", "<Plug>(ArgotAdd)", function()
  require("argot.lookup").add()
end, { desc = "argot: add entry" })

vim.keymap.set("n", "<Plug>(ArgotSearch)", function()
  -- prefer argot's own telescope picker (live fuzzy bar) when telescope is
  -- around; fall back to the vim.ui.select flow otherwise
  local ok = pcall(function()
    require("telescope").extensions.argot.argot()
  end)
  if not ok then
    vim.cmd("Argot search")
  end
end, { desc = "argot: search all stores" })

vim.keymap.set("n", "<Plug>(ArgotList)", function()
  vim.cmd("Argot list")
end, { desc = "argot: list entries" })

vim.keymap.set("n", "<Plug>(ArgotProjects)", function()
  vim.cmd("Argot projects")
end, { desc = "argot: projects browser" })

-- Startup surface: one user command and the <Plug> contract, zero requires.
-- Everything loads on first use.

if vim.g.loaded_gloss then
  return
end
vim.g.loaded_gloss = 1

vim.api.nvim_create_user_command("Gloss", function(cmd)
  require("gloss.command").dispatch(cmd)
end, {
  nargs = "*",
  range = true,
  desc = "Project glossary",
  complete = function(arglead, cmdline, _)
    return require("gloss.command").complete(arglead, cmdline)
  end,
})

vim.keymap.set({ "n", "x" }, "<Plug>(GlossLookup)", function()
  require("gloss.lookup").run()
end, { desc = "gloss: lookup" })

vim.keymap.set("n", "<Plug>(GlossAdd)", function()
  require("gloss.lookup").add()
end, { desc = "gloss: add entry" })

vim.keymap.set("n", "<Plug>(GlossSearch)", function()
  -- prefer gloss's own telescope picker (live fuzzy bar) when telescope is
  -- around; fall back to the vim.ui.select flow otherwise
  local ok = pcall(function()
    require("telescope").extensions.gloss.gloss()
  end)
  if not ok then
    vim.cmd("Gloss search")
  end
end, { desc = "gloss: search all stores" })

vim.keymap.set("n", "<Plug>(GlossList)", function()
  vim.cmd("Gloss list")
end, { desc = "gloss: list entries" })

vim.keymap.set("n", "<Plug>(GlossProjects)", function()
  vim.cmd("Gloss projects")
end, { desc = "gloss: projects browser" })

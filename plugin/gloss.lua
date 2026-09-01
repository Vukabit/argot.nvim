-- Startup surface: one user command, zero requires. Everything loads on
-- first use.

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

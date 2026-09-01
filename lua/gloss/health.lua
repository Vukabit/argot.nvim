--- :checkhealth gloss

local M = {}

function M.check()
  local health = vim.health
  health.start("gloss.nvim")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim >= 0.11")
  else
    health.error("gloss.nvim requires Neovim 0.11+")
  end

  local has_sqlite = pcall(require, "sqlite.db")
  if has_sqlite then
    local opened, err = pcall(function()
      local db = require("gloss.store.sqlite").open(":memory:")
      db:close()
    end)
    if opened then
      health.ok("sqlite.lua and libsqlite3 are working (SQLite backend available)")
    else
      health.warn("sqlite.lua is installed but opening a database failed: " .. tostring(err))
    end
  else
    health.warn(
      "kkharji/sqlite.lua is not installed: the global dictionary and out-of-repo project"
        .. " stores are unavailable; in-repo (JSONL) glossaries still work"
    )
  end

  if vim.fn.executable("rg") == 1 then
    health.ok("ripgrep found (used for AI context gathering)")
  else
    health.warn("ripgrep not found: AI providers will receive less codebase context")
  end

  local data_dir = require("gloss.config").data_dir()
  vim.fn.mkdir(data_dir, "p")
  if vim.fn.filewritable(data_dir) == 2 then
    health.ok("data directory is writable: " .. data_dir)
  else
    health.error("data directory is not writable: " .. data_dir)
  end
end

return M

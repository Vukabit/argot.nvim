--- :checkhealth argot

local M = {}

function M.check()
  local health = vim.health
  health.start("argot.nvim")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim >= 0.11")
  else
    health.error("argot.nvim requires Neovim 0.11+")
  end

  local has_sqlite = pcall(require, "sqlite.db")
  if has_sqlite then
    local opened, err = pcall(function()
      local db = require("argot.store.sqlite").open(":memory:")
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

  local data_dir = require("argot.config").data_dir()
  vim.fn.mkdir(data_dir, "p")
  if vim.fn.filewritable(data_dir) == 2 then
    health.ok("data directory is writable: " .. data_dir)
  else
    health.error("data directory is not writable: " .. data_dir)
  end

  health.start("current project")
  local project = require("argot.project")
  local ok, desc = pcall(project.resolve)
  if not ok then
    health.warn("could not resolve the project: " .. tostring(desc))
  elseif desc.mode == "in_repo" then
    health.ok(("in-repo mode: %s"):format(desc.path))
  elseif desc.mode == "out_of_repo" and desc.registry_id then
    health.ok(("registered out-of-repo project, store at %s"):format(desc.path))
  elseif desc.relink then
    health.warn(
      ("registry knows this repo under another path (%s); run :Argot init or a lookup to relink"):format(
        desc.relink.old_root
      )
    )
  else
    health.info(
      "project not registered yet (saving an entry to the project scope registers it, or run :Argot init)"
    )
  end

  local provider = require("argot.config").options.ai.provider
  if provider then
    local consented = ok and desc and require("argot.ai").consent(desc.root)
    health.ok(
      ("AI provider configured: %s (consent here: %s)"):format(
        provider.name or "unnamed",
        consented and "on" or "off; run :Argot ai on"
      )
    )
  else
    health.info("no AI provider configured (optional; see :h argot-ai)")
  end

  local skipped = require("argot.keymaps").skipped
  if #skipped == 0 then
    health.ok("no keymap conflicts")
  else
    for _, skip in ipairs(skipped) do
      health.warn(
        ("keymap %s (%s mode, action %s) not installed: already mapped"):format(
          skip.lhs,
          skip.mode,
          skip.action
        )
      )
    end
  end
end

return M

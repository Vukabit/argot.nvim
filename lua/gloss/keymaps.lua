--- The opt-in curated keymap set. <Plug> mappings (defined in
--- plugin/gloss.lua) are the stable contract; this module only installs the
--- convenience layer, never clobbers an existing mapping, and remembers what
--- it skipped so :checkhealth can report it.

local config = require("gloss.config")

local M = {}

---@type {lhs: string, mode: string, action: string}[]
M.skipped = {}

local ACTIONS = {
  lookup = { plug = "<Plug>(GlossLookup)", suffix = "g", modes = { "n", "x" } },
  add = { plug = "<Plug>(GlossAdd)", suffix = "a", modes = { "n" } },
  search = { plug = "<Plug>(GlossSearch)", suffix = "s", modes = { "n" } },
  list = { plug = "<Plug>(GlossList)", suffix = "l", modes = { "n" } },
  projects = { plug = "<Plug>(GlossProjects)", suffix = "p", modes = { "n" } },
}

local function existing_map(lhs, mode)
  local typed = lhs:gsub("<[Ll]eader>", vim.g.mapleader or "\\")
  local map = vim.fn.maparg(typed, mode, false, true)
  if type(map) ~= "table" or vim.tbl_isempty(map) then
    return nil
  end
  return map
end

function M.install()
  M.skipped = {}
  local km = config.options.keymaps
  if not km then
    return
  end
  local spec = km == true and {} or km
  local prefix = spec.prefix or "<leader>g"
  for name, action in vim.spairs(ACTIONS) do
    local lhs = spec[name]
    if lhs ~= false then
      lhs = type(lhs) == "string" and lhs or (prefix .. action.suffix)
      for _, mode in ipairs(action.modes) do
        local current = existing_map(lhs, mode)
        -- reinstalling over our own mapping is fine; anything else is skipped
        if current and not (current.rhs or ""):find("(Gloss", 1, true) then
          M.skipped[#M.skipped + 1] = { lhs = lhs, mode = mode, action = name }
        else
          vim.keymap.set(mode, lhs, action.plug, { desc = "gloss: " .. name })
        end
      end
    end
  end
  for _, skip in ipairs(M.skipped) do
    vim.notify(
      ("gloss: keymap %s (%s) not installed, already mapped; see :checkhealth gloss"):format(
        skip.lhs,
        skip.action
      ),
      vim.log.levels.WARN
    )
  end
  pcall(function()
    -- selene: allow(mixed_table) -- which-key's spec format is mixed by design
    require("which-key").add({ { prefix, group = "gloss" } })
  end)
end

return M

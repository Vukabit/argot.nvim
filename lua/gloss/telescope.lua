--- The telescope picker behind :Telescope gloss. A thin skin over the
--- search engine: same items, same origin labels, live fuzzy filtering,
--- and direct mappings for the cross-store actions.

local M = {}

--- Telescope-shaped entries (pure; testable without telescope).
---@param query string?
---@return table[]
function M.entries(query)
  local search = require("gloss.search")
  local items = search.filter(search.collect(), query or "")
  return vim.tbl_map(function(item)
    return {
      value = item,
      display = search.format_item(item),
      ordinal = table.concat({
        item.entry.term,
        table.concat(item.entry.aliases or {}, " "),
        item.entry.expansion or "",
        "#" .. table.concat(item.entry.tags or {}, " #"),
        item.label,
      }, " "),
    }
  end, items)
end

---@param opts table? telescope options; opts.query pre-filters
function M.picker(opts)
  opts = opts or {}
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local search = require("gloss.search")

  pickers
    .new(opts, {
      prompt_title = "gloss",
      finder = finders.new_table({
        results = M.entries(opts.query),
        entry_maker = function(entry)
          return entry
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        local function with_selected(fn)
          return function()
            local entry = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if entry and entry.value then
              fn(entry.value)
            end
          end
        end
        actions.select_default:replace(with_selected(function(item)
          require("gloss.defbuf").open(item.entry, { store = item.store, scope = item.label })
        end))
        map(
          { "i", "n" },
          "<C-y>",
          with_selected(function(item)
            search._pick_destination(item, false)
          end)
        )
        map(
          { "i", "n" },
          "<C-o>",
          with_selected(function(item)
            search._pick_destination(item, true)
          end)
        )
        map(
          { "i", "n" },
          "<C-d>",
          with_selected(function(item)
            search.delete_item(item)
          end)
        )
        return true
      end,
    })
    :find()
end

return M

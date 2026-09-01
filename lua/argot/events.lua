--- User autocmd events. Everything that mutates state announces it here so
--- UIs (and user config) can react without core knowing about them:
---   ArgotEntryAdded / ArgotEntryChanged / ArgotEntryRemoved
---     data = { term, scope }
---   ArgotStoreChanged
---     data = {} (a store was created, migrated, or replaced wholesale)

local M = {}

---@param event string
---@param data table
function M.emit(event, data)
  vim.api.nvim_exec_autocmds("User", { pattern = event, data = data })
end

return M

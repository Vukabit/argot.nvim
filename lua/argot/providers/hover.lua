--- hover.nvim provider module. Add it to hover.nvim's provider list:
---
---   require("hover").config({
---     providers = { "hover.providers.lsp", "argot.providers.hover" },
---   })

return require("argot.hover").provider()

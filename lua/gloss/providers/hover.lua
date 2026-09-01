--- hover.nvim provider module. Add it to hover.nvim's provider list:
---
---   require("hover").config({
---     providers = { "hover.providers.lsp", "gloss.providers.hover" },
---   })

return require("gloss.hover").provider()

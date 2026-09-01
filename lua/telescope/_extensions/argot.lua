local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("argot: the telescope extension requires nvim-telescope/telescope.nvim")
end

return telescope.register_extension({
  exports = {
    argot = function(opts)
      require("argot.telescope").picker(opts)
    end,
  },
})

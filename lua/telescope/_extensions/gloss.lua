local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("gloss: the telescope extension requires nvim-telescope/telescope.nvim")
end

return telescope.register_extension({
  exports = {
    gloss = function(opts)
      require("gloss.telescope").picker(opts)
    end,
  },
})

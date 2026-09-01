local eq = MiniTest.expect.equality

local config = require("gloss.config")
local defbuf = require("gloss.defbuf")
local jsonl = require("gloss.store.jsonl")
local links = require("gloss.links")
local project = require("gloss.project")

local tmpdir, old_cwd

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      old_cwd = vim.uv.cwd()
      config.setup({ data_dir = vim.fs.joinpath(tmpdir, "data") })
      project.drop_handles()
    end,
    post_case = function()
      vim.cmd.cd(old_cwd)
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= "" then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buf):find("^gloss://") then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
      project.drop_handles()
      config.setup({})
      vim.fn.delete(tmpdir, "rf")
    end,
  },
})

local function make_project(entries)
  local root = vim.fs.joinpath(tmpdir, "proj")
  vim.fn.mkdir(root, "p")
  local res = project.init_in_repo(root)
  local store = jsonl.open(res.path)
  for _, entry in ipairs(entries) do
    store:upsert(entry)
  end
  vim.cmd.cd(root)
  return store
end

T["extract finds targets, trims, skips empties"] = function()
  eq(links.extract("see [[DLQ]] and [[ dead letter queue ]]"), { "DLQ", "dead letter queue" })
  eq(links.extract("no links here"), {})
  eq(links.extract("empty [[]] and [[  ]] ignored"), {})
  eq(links.extract(nil), {})
end

T["at_cursor resolves only when the cursor sits on a link"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "see [[DLQ]] then [[SQS]] end" })
  vim.api.nvim_set_current_buf(buf)

  vim.api.nvim_win_set_cursor(0, { 1, 6 }) -- inside [[DLQ]]
  eq(links.at_cursor(), "DLQ")
  vim.api.nvim_win_set_cursor(0, { 1, 19 }) -- inside [[SQS]]
  eq(links.at_cursor(), "SQS")
  vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- on "see"
  eq(links.at_cursor(), nil)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["omnifunc completes terms after double brackets and closes them"] = function()
  make_project({ { term = "DLQ", definition = "d" }, { term = "DNS", definition = "d" } })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "see [[D" })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 1, 7 })

  eq(links.omnifunc(1), 6)
  local matches = links.omnifunc(0, "D")
  local words = vim.tbl_map(function(match)
    return match.word
  end, matches)
  table.sort(words)
  eq(words, { "DLQ]]", "DNS]]" })

  -- not after [[: cancel silently
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "plain text" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  eq(links.omnifunc(1), -3)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["following a link opens the target entry"] = function()
  local store = make_project({
    { term = "DLQ", definition = "see [[SQS]] for the transport" },
    { term = "SQS", definition = "Simple Queue Service" },
  })
  local buf, win = defbuf.open(store:get("DLQ"), { store = store, scope = "project" })
  -- cursor onto [[SQS]] in the body (line 6)
  vim.api.nvim_win_set_cursor(win, { 6, 6 })
  eq(defbuf._follow(buf, win), true)

  local current = vim.api.nvim_get_current_buf()
  eq(vim.api.nvim_buf_get_name(current):find("SQS") ~= nil, true)
  local text = table.concat(vim.api.nvim_buf_get_lines(current, 0, -1, false), "\n")
  eq(text:find("Simple Queue Service") ~= nil, true)
end

T["following an undefined link offers a prefilled new entry"] = function()
  local store = make_project({ { term = "DLQ", definition = "handled by the [[reaper]]" } })
  local buf, win = defbuf.open(store:get("DLQ"), { store = store, scope = "project" })
  vim.api.nvim_win_set_cursor(win, { 6, 17 })
  eq(defbuf._follow(buf, win), true)

  local current = vim.api.nvim_get_current_buf()
  eq(vim.api.nvim_buf_get_lines(current, 0, 1, false)[1], "term: reaper")
end

T["follow refuses to abandon unsaved edits, and off-link does nothing"] = function()
  local store =
    make_project({ { term = "DLQ", definition = "see [[SQS]]" }, { term = "SQS", definition = "d" } })
  local buf, win = defbuf.open(store:get("DLQ"), { store = store, scope = "project" })

  vim.api.nvim_win_set_cursor(win, { 1, 0 }) -- header line, no link
  eq(defbuf._follow(buf, win), false)

  vim.api.nvim_buf_set_lines(buf, 5, 6, false, { "edited see [[SQS]]" })
  vim.api.nvim_win_set_cursor(win, { 6, 13 })
  eq(defbuf._follow(buf, win), true)
  eq(vim.api.nvim_get_current_buf(), buf) -- still here: modified
end

T["doctor reports dangling links with the fix"] = function()
  make_project({
    { term = "DLQ", definition = "see [[SQS]] and the [[ghost protocol]]" },
    { term = "SQS", definition = "d" },
  })
  local lines, problems = require("gloss.doctor").report()
  local text = table.concat(lines, "\n")
  eq(problems, 1)
  eq(text:find("links to %[%[ghost protocol%]%]") ~= nil, true)
  eq(text:find(":Gloss add ghost protocol") ~= nil, true)
end

return T

--- The AI miss handler. Three rules keep this clean:
---   1. Core never talks to a model; a provider is a table with `name` and
---      `propose(request, callback)`.
---   2. Core owns context gathering (surrounding lines, capped ripgrep
---      usages, README head), so every provider benefits equally.
---   3. Nothing is auto-saved: proposals open in the review buffer marked
---      source = "ai", and sending code context anywhere is inert until
---      `:Gloss ai on` in that project (consent is per-user local state,
---      never read from the repo).
--- A provider that is unsure may answer with `questions` instead of a
--- definition; gloss relays them to the user and re-asks once.

local config = require("gloss.config")

local M = {}

-- one clarifying-questions round trip, then the provider must answer
M.ROUND_LIMIT = 2

local warned_consent = false

local function consent_path()
  return vim.fs.joinpath(config.data_dir(), "ai_consent.json")
end

---@param root string canonical project root (project.detect)
---@return boolean
function M.consent(root)
  local data = require("gloss.util").read_json(consent_path())
  return type(data) == "table" and type(data.projects) == "table" and data.projects[root] == true
end

---@param root string
---@param on boolean
function M.set_consent(root, on)
  local util = require("gloss.util")
  local data = util.read_json(consent_path()) or { version = 1, projects = {} }
  data.projects = type(data.projects) == "table" and data.projects or {}
  data.projects[root] = on and true or nil
  util.write_json(consent_path(), data)
end

--- Assemble the provider-agnostic context bundle.
---@param word string
---@param opts? {startpath?: string, buf?: integer, lnum?: integer}
---@return table request
function M.build_request(word, opts)
  opts = opts or {}
  local project = require("gloss.project")
  local root = (project.detect(opts.startpath))
  local ctx = config.options.ai.context or {}
  local req = { term = word, root = root }

  local buf = opts.buf or 0
  local bufname = vim.api.nvim_buf_get_name(buf)
  if bufname ~= "" and vim.api.nvim_buf_is_loaded(buf) then
    req.file = vim.fs.normalize(bufname)
    req.filetype = vim.bo[buf].filetype
    local around = ctx.lines or 8
    local lnum = opts.lnum or vim.api.nvim_win_get_cursor(0)[1]
    local first = math.max(0, lnum - 1 - around)
    req.context = table.concat(vim.api.nvim_buf_get_lines(buf, first, lnum + around, false), "\n")
  end

  if vim.fn.executable("rg") == 1 then
    local ok, proc = pcall(vim.system, {
      "rg",
      "--no-heading",
      "--line-number",
      "--fixed-strings",
      "--word-regexp",
      "--max-count",
      "3",
      "--",
      word,
      root,
    }, { text = true })
    if ok then
      local res = proc:wait(2000)
      if res.code == 0 and res.stdout and res.stdout ~= "" then
        local lines = vim.split(res.stdout, "\n", { trimempty = true })
        req.usages = vim.list_slice(lines, 1, ctx.usages or 20)
      end
    end
  end

  for _, name in ipairs({ "README.md", "README.markdown", "README" }) do
    local path = vim.fs.joinpath(root, name)
    if vim.fn.filereadable(path) == 1 then
      req.readme = table.concat(vim.list_slice(vim.fn.readfile(path), 1, 40), "\n")
      break
    end
  end
  return req
end

--- Try to dispatch the AI handler for a missed word. Returns false (without
--- side effects beyond a one-time hint) when no provider is configured or
--- this project has no consent, so the miss chain can fall through.
---@param word string
---@param opts? table passed to build_request
---@return boolean dispatched
function M.propose_for(word, opts)
  local provider = config.options.ai.provider
  if not (type(provider) == "table" and type(provider.propose) == "function") then
    return false
  end
  -- consent must be keyed to the project whose source the context bundle
  -- actually carries: the current buffer's, not the cwd's
  opts = opts and vim.deepcopy(opts) or {}
  if not opts.startpath then
    local bufname = vim.api.nvim_buf_get_name(opts.buf or 0)
    if bufname ~= "" then
      opts.startpath = vim.fs.dirname(vim.fs.normalize(bufname))
    end
  end
  local root = (require("gloss.project").detect(opts.startpath))
  if not M.consent(root) then
    if not warned_consent then
      warned_consent = true
      vim.notify(
        "gloss: an AI provider is configured but not enabled here; run :Gloss ai on",
        vim.log.levels.INFO
      )
    end
    return false
  end
  M._ask(provider, M.build_request(word, opts), 1)
  return true
end

function M._ask(provider, req, round)
  vim.notify(("gloss: asking %s about %q..."):format(provider.name or "the AI provider", req.term))
  local ok, err = pcall(
    provider.propose,
    req,
    vim.schedule_wrap(function(res)
      M._handle(provider, req, round, res)
    end)
  )
  if not ok then
    vim.notify("gloss: provider error: " .. tostring(err), vim.log.levels.ERROR)
  end
end

local function sane_questions(res)
  local out = {}
  if type(res.questions) == "table" then
    for _, question in ipairs(res.questions) do
      if type(question) == "string" and question ~= "" then
        out[#out + 1] = question
      end
    end
  end
  return out
end

function M._handle(provider, req, round, res)
  res = type(res) == "table" and res or {}
  local definition = type(res.definition) == "string" and res.definition or nil
  local questions = sane_questions(res)

  if #questions > 0 and round < M.ROUND_LIMIT then
    M._interview(provider, req, questions)
    return
  end
  if not definition then
    vim.notify("gloss: the provider returned no usable proposal; opening a blank entry", vim.log.levels.WARN)
    require("gloss.lookup").add(req.term)
    return
  end

  local entry = {
    term = req.term,
    expansion = type(res.expansion) == "string" and res.expansion or nil,
    tags = type(res.tags) == "table" and vim.tbl_filter(function(t)
      return type(t) == "string"
    end, res.tags) or nil,
    definition = definition,
    source = "ai",
  }
  local name = provider.name or "AI"
  if type(res.confidence) == "number" then
    vim.notify(
      ("gloss: proposal from %s (confidence %.2f); review and :w to keep"):format(name, res.confidence)
    )
  else
    vim.notify(("gloss: proposal from %s; review and :w to keep"):format(name))
  end
  require("gloss.defbuf").open(entry, {})
end

function M._interview(provider, req, questions)
  local answers = {}
  local function ask(i)
    if i > #questions then
      local followup = vim.deepcopy(req)
      followup.answers = answers
      M._ask(provider, followup, 2)
      return
    end
    vim.ui.input(
      { prompt = ("gloss [%s]: %s "):format(provider.name or "AI", questions[i]) },
      function(answer)
        if answer == nil then
          vim.notify("gloss: cancelled", vim.log.levels.INFO)
          return
        end
        answers[#answers + 1] = { question = questions[i], answer = answer }
        ask(i + 1)
      end
    )
  end
  ask(1)
end

return M

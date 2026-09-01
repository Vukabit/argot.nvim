local eq = MiniTest.expect.equality

local ai = require("gloss.ai")
local config = require("gloss.config")
local defbuf = require("gloss.defbuf")

local tmpdir

local function close_floats()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

local function find_gloss_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf):find("^gloss://") then
      return buf
    end
  end
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      config.setup({ data_dir = vim.fs.joinpath(tmpdir, "data") })
    end,
    post_case = function()
      close_floats()
      local buf = find_gloss_buf()
      if buf then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
      config.setup({})
      vim.fn.delete(tmpdir, "rf")
    end,
  },
})

T["consent is off by default, per-root, and persists"] = function()
  eq(ai.consent(tmpdir), false)
  ai.set_consent(tmpdir, true)
  eq(ai.consent(tmpdir), true)
  eq(ai.consent(tmpdir .. "/other"), false)
  ai.set_consent(tmpdir, false)
  eq(ai.consent(tmpdir), false)
end

T["build_request bundles buffer context, usages, and the readme"] = function()
  local root = vim.fs.joinpath(tmpdir, "proj")
  vim.fn.mkdir(root, "p")
  vim.fn.writefile({ "# my project", "it processes the DLQ nightly" }, vim.fs.joinpath(root, "README.md"))
  vim.fn.writefile({ "push_to_dlq()", "-- DLQ drain loop" }, vim.fs.joinpath(root, "worker.lua"))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(root, "main.lua"))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local q = DLQ.new()", "q:drain()" })

  local req = ai.build_request("DLQ", { startpath = root, buf = buf, lnum = 1 })
  eq(req.term, "DLQ")
  eq(req.root:find("proj") ~= nil, true)
  eq(req.file:find("main%.lua") ~= nil, true)
  eq(req.context:find("DLQ.new") ~= nil, true)
  eq(req.readme:find("my project") ~= nil, true)
  if vim.fn.executable("rg") == 1 then
    eq(#req.usages >= 1, true)
  end
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["propose_for declines without consent"] = function()
  config.setup({
    data_dir = vim.fs.joinpath(tmpdir, "data"),
    ai = { provider = { name = "fake", propose = function() end } },
  })
  eq(ai.propose_for("DLQ"), false)
end

T["a proposal opens the review buffer marked ai; verbatim accept stays ai"] = function()
  local store_calls = {}
  local fake_store = {
    upsert = function(_, entry)
      store_calls[#store_calls + 1] = entry
      return vim.deepcopy(entry)
    end,
    get = function()
      return nil
    end,
    delete = function() end,
  }
  config.setup({
    data_dir = vim.fs.joinpath(tmpdir, "data"),
    ai = {
      provider = {
        name = "fake",
        propose = function(req, cb)
          cb({ definition = "queue for poison messages", expansion = "dead letter queue", confidence = 0.9 })
        end,
      },
    },
  })
  ai.set_consent((require("gloss.project").detect()), true)

  eq(ai.propose_for("DLQ"), true)
  vim.wait(1000, find_gloss_buf)
  local buf = find_gloss_buf()
  eq(buf ~= nil, true)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  eq(text:find("queue for poison messages") ~= nil, true)
  eq(text:find("expansion: dead letter queue") ~= nil, true)

  -- accept verbatim: source stays "ai"
  local orig_select, orig_scope = vim.ui.select, defbuf._scope_store
  vim.ui.select = function(_, _, cb)
    cb("project")
  end
  defbuf._scope_store = function()
    return fake_store
  end
  vim.api.nvim_set_current_buf(buf)
  vim.cmd.write()
  vim.ui.select, defbuf._scope_store = orig_select, orig_scope

  eq(#store_calls, 1)
  eq(store_calls[1].source, "ai")
end

T["an edited proposal becomes ai_edited"] = function()
  local saved
  local fake_store = {
    upsert = function(_, entry)
      saved = entry
      return vim.deepcopy(entry)
    end,
    get = function()
      return nil
    end,
    delete = function() end,
  }
  config.setup({
    data_dir = vim.fs.joinpath(tmpdir, "data"),
    ai = {
      provider = {
        name = "fake",
        propose = function(_, cb)
          cb({ definition = "machine words" })
        end,
      },
    },
  })
  ai.set_consent((require("gloss.project").detect()), true)
  ai.propose_for("DLQ")
  vim.wait(1000, find_gloss_buf)
  local buf = find_gloss_buf()

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  lines[#lines] = "human words"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local orig_select, orig_scope = vim.ui.select, defbuf._scope_store
  vim.ui.select = function(_, _, cb)
    cb("project")
  end
  defbuf._scope_store = function()
    return fake_store
  end
  vim.api.nvim_set_current_buf(buf)
  vim.cmd.write()
  vim.ui.select, defbuf._scope_store = orig_select, orig_scope

  eq(saved.source, "ai_edited")
end

T["questions run one interview round, then the provider must answer"] = function()
  local rounds = {}
  config.setup({
    data_dir = vim.fs.joinpath(tmpdir, "data"),
    ai = {
      provider = {
        name = "fake",
        propose = function(req, cb)
          rounds[#rounds + 1] = vim.deepcopy(req)
          if req.answers then
            cb({ definition = "informed by " .. req.answers[1].answer })
          else
            cb({ questions = { "Which queue system?" } })
          end
        end,
      },
    },
  })
  ai.set_consent((require("gloss.project").detect()), true)

  local orig_input = vim.ui.input
  vim.ui.input = function(_, cb)
    cb("SQS")
  end
  ai.propose_for("DLQ")
  vim.wait(1000, find_gloss_buf)
  vim.ui.input = orig_input

  eq(#rounds, 2)
  eq(rounds[2].answers[1].question, "Which queue system?")
  eq(rounds[2].answers[1].answer, "SQS")
  local buf = find_gloss_buf()
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  eq(text:find("informed by SQS") ~= nil, true)
end

T["cli provider round-trips json, tolerates fences, rejects garbage"] = function()
  local cli = require("gloss.providers.cli")

  local function run(shell_cmd)
    local provider = cli.new({ cmd = { "sh", "-c", shell_cmd }, name = "sh" })
    local result, done
    provider.propose({ term = "DLQ" }, function(res)
      result, done = res, true
    end)
    vim.wait(2000, function()
      return done
    end)
    return result
  end

  local clean = run([[cat > /dev/null; printf '{"definition": "from cli", "confidence": 0.5}']])
  eq(clean.definition, "from cli")

  local fenced =
    run([[cat > /dev/null; printf 'Sure! Here you go:\n```json\n{"definition": "fenced"}\n```\n']])
  eq(fenced.definition, "fenced")

  eq(run([[cat > /dev/null; echo "no json here"]]), nil)
  eq(run([[cat > /dev/null; exit 3]]), nil)
end

T["cli provider feeds the prompt on stdin"] = function()
  local cli = require("gloss.providers.cli")
  local out = vim.fs.joinpath(tmpdir, "stdin.txt")
  local provider = cli.new({ cmd = { "sh", "-c", ("cat > %s; printf '{}'"):format(out) } })
  local done
  provider.propose({ term = "DLQ", root = "/x" }, function()
    done = true
  end)
  vim.wait(2000, function()
    return done
  end)
  local prompt = table.concat(vim.fn.readfile(out), "\n")
  eq(prompt:find("DLQ", 1, true) ~= nil, true)
  eq(prompt:find("ONLY a JSON object", 1, true) ~= nil, true)
end

return T

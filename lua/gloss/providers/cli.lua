--- The generic CLI provider: spawn any command, prompt on stdin, JSON on
--- stdout. This single adapter makes `claude -p`, `llm`, `ollama run`, or a
--- homegrown agent script work with zero SDK dependencies:
---
---   ai = { provider = require("gloss.providers.cli").new({ cmd = { "claude", "-p" } }) }

local M = {}

---@param req table the gloss request bundle
---@return string
function M.default_prompt(req)
  return table.concat({
    "You write glossary entries for terms and acronyms found in a codebase.",
    "Using the JSON request below, define the term concisely:",
    "- Lead with the general meaning in one or two plain sentences.",
    "- Only when the codebase context shows a project-specific convention,",
    "  add ONE short sentence about how this project uses the term. Never",
    "  enumerate code sites, constants, or file names unless the term IS",
    "  that identifier.",
    "- A truly project-internal term (no general meaning) is defined from",
    "  the context alone, still briefly.",
    "- Keep the whole definition under 80 words.",
    "Respond with ONLY a JSON object, no prose and no code fences:",
    '  {"definition": "<markdown>", "expansion": "<acronym expansion or omit>",',
    '   "tags": ["<lowercase tag>", ...], "confidence": <0.0-1.0>,',
    '   "questions": ["<question for the user>", ...]}',
    "Use `questions` (and omit `definition`) only when the context is truly",
    "insufficient. If the request carries `answers`, this is your final",
    "round: you must produce a definition.",
    "",
    "Request:",
    vim.json.encode(req),
  }, "\n")
end

local function decode_response(stdout)
  local raw = vim.trim(stdout or "")
  local ok, decoded = pcall(vim.json.decode, raw)
  if ok and type(decoded) == "table" then
    return decoded
  end
  -- models love wrapping JSON in fences or prose; take the first balanced
  -- brace block that decodes
  local blob = raw:match("(%b{})")
  if blob then
    local ok2, decoded2 = pcall(vim.json.decode, blob)
    if ok2 and type(decoded2) == "table" then
      return decoded2
    end
  end
  return nil
end

---@param opts {cmd: string[], name?: string, timeout?: integer, prompt?: fun(req: table): string}
---@return table provider
function M.new(opts)
  assert(
    type(opts) == "table" and type(opts.cmd) == "table" and #opts.cmd > 0,
    "gloss: the cli provider needs opts.cmd, e.g. { cmd = { 'claude', '-p' } }"
  )
  local provider = { name = opts.name or vim.fs.basename(opts.cmd[1]) }

  ---@param req table
  ---@param cb fun(res: table?)
  function provider.propose(req, cb)
    local prompt = (opts.prompt or M.default_prompt)(req)
    local ok, err = pcall(vim.system, opts.cmd, {
      stdin = prompt,
      text = true,
      timeout = opts.timeout or 60000,
    }, function(out)
      if out.code ~= 0 then
        cb(nil)
        return
      end
      cb(decode_response(out.stdout))
    end)
    if not ok then
      vim.schedule(function()
        vim.notify("gloss: failed to run the provider command: " .. tostring(err), vim.log.levels.ERROR)
      end)
      cb(nil)
    end
  end

  return provider
end

return M

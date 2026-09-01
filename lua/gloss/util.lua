--- Small shared helpers: identifiers and atomic JSON files.

local M = {}

---@return string 32 hex chars, permanent identity for a project store
function M.uuid()
  local ok, bytes = pcall(vim.uv.random, 16)
  if ok and type(bytes) == "string" and #bytes == 16 then
    return (bytes:gsub(".", function(c)
      return ("%02x"):format(c:byte())
    end))
  end
  -- fallback when uv.random is unavailable
  math.randomseed(vim.uv.hrtime() % 2147483647)
  local hex = {}
  for _ = 1, 32 do
    hex[#hex + 1] = ("%x"):format(math.random(0, 15))
  end
  return table.concat(hex)
end

---@param path string
---@return table? decoded
---@return boolean invalid true when the file exists but cannot be parsed
function M.read_json(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil, false
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if ok and type(decoded) == "table" then
    return decoded, false
  end
  return nil, true
end

--- Atomic write: tmp file + rename, like the JSONL store.
---@param path string
---@param tbl table
function M.write_json(path, tbl)
  local dir = vim.fs.dirname(path)
  if dir and dir ~= "" then
    vim.fn.mkdir(dir, "p")
  end
  -- pid-unique tmp name so concurrent Neovim instances never truncate each
  -- other's in-flight write
  local tmp = ("%s.%d.tmp"):format(path, vim.uv.os_getpid())
  if vim.fn.writefile({ vim.json.encode(tbl) }, tmp) ~= 0 then
    error(("gloss: failed writing %s"):format(tmp))
  end
  local ok, err = vim.uv.fs_rename(tmp, path)
  if not ok then
    vim.uv.fs_unlink(tmp)
    error(("gloss: failed replacing %s: %s"):format(path, err or "unknown error"))
  end
end

return M

local M = {}

-- Read a file and return its contents, or nil + error.
local function read_file(path)
  local fh, err = io.open(path, "rb")
  if not fh then return nil, err end
  local data = fh:read("*a")
  fh:close()
  return data
end

-- hash_filename(path) -> 8-char lowercase hex sha1 prefix, or nil + err.
function M.hash_filename(path)
  local data, err = read_file(path)
  if not data then return nil, err end

  -- Write data to a temp file so we can feed it to shasum via stdin redirect.
  local tmpname = os.tmpname()
  local tf, terr = io.open(tmpname, "wb")
  if not tf then return nil, terr end
  tf:write(data)
  tf:close()

  local rp = io.popen("shasum -a 1 < " .. string.format("%q", tmpname), "r")
  if not rp then
    os.remove(tmpname)
    return nil, "io.popen failed"
  end
  local out = rp:read("*l") or ""
  rp:close()
  os.remove(tmpname)

  -- shasum output format: "<40 hex>  -\n"
  local hex = out:match("^(%x+)")
  if not hex or #hex < 8 then
    return nil, "shasum produced unexpected output: " .. out
  end
  return hex:sub(1, 8):lower()
end

return M

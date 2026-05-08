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

-- Single-letter ssh options that consume a separate following argv token.
-- Fused forms like `-p22` and `-oKEY=VALUE` are intentionally NOT listed
-- here as their own keys: they pass through the generic "-" boolean branch
-- below as a single preserved token, which is exactly what `ssh -G` and
-- `scp` accept on replay. If you "refine" the parser to split fused forms,
-- add a regression test for `-p22` first (see spec/parse_spec.lua).
local ARG_CONSUMING_FLAGS = {
  ["-b"]=true, ["-c"]=true, ["-D"]=true, ["-E"]=true, ["-e"]=true,
  ["-F"]=true, ["-I"]=true, ["-i"]=true, ["-J"]=true, ["-L"]=true,
  ["-l"]=true, ["-m"]=true, ["-O"]=true, ["-o"]=true, ["-p"]=true,
  ["-Q"]=true, ["-R"]=true, ["-S"]=true, ["-W"]=true, ["-w"]=true,
}

local function basename(path)
  return (path:match("([^/]+)$")) or path
end

-- parse_ssh_argv(argv) -> {destination, replay_flags} | nil
function M.parse_ssh_argv(argv)
  if not argv or #argv == 0 then return nil end
  if basename(argv[1]) ~= "ssh" then return nil end

  local replay = {}
  local i = 2
  while i <= #argv do
    local tok = argv[i]
    if tok == "--" then
      -- everything after is positional; first one is destination
      i = i + 1
      if i > #argv then return nil end
      return { destination = argv[i], replay_flags = replay }
    elseif ARG_CONSUMING_FLAGS[tok] then
      local val = argv[i + 1]
      if not val then return nil end
      table.insert(replay, tok)
      table.insert(replay, val)
      i = i + 2
    elseif tok:sub(1, 1) == "-" then
      -- bool flag (handled fully in Task 5); for now keep it
      table.insert(replay, tok)
      i = i + 1
    else
      -- first non-flag token is destination
      return { destination = tok, replay_flags = replay }
    end
  end
  return nil  -- never found a destination
end

-- escape_remote_path validates that a remote path contains only
-- characters we generate ourselves. We never need exotic paths;
-- rejecting anything fancy is safer than escaping.
function M.escape_remote_path(s)
  if type(s) ~= "string" then return nil, "not a string" end
  if not s:match("^[%w/_%-%.]+$") then
    return nil, "remote path contains disallowed characters"
  end
  return s
end

return M

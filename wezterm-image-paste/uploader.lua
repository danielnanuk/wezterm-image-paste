-- wezterm-image-paste/uploader.lua
--
-- uploader.run(target, local_path, remote_dir) -> remote_path | (nil, err)
--
-- Uploads a local PNG to a remote host over SCP, using content-addressing
-- (sha1[:8]) to skip redundant transfers. Both ssh and scp invocations
-- include target.replay_flags so they take the same network path as the
-- user's interactive ssh session.

local run = require("wezterm-image-paste.run")
local parse = require("wezterm-image-paste.parse")

local M = {}

-- ControlMaster flags appended after replay_flags in every ssh/scp call.
-- Using ControlMaster=auto means the first call opens a master connection
-- that subsequent calls reuse, so the ssh precheck and the scp share one
-- TCP handshake (important over jump-host chains).
local CONTROL_FLAGS = {
  "-o", "ControlMaster=auto",
  "-o", "ControlPath=~/.ssh/cm-%r@%h:%p",
  "-o", "ControlPersist=10m",
  "-o", "ConnectTimeout=10",
}

local function concat(a, b)
  local out = {}
  for _, v in ipairs(a) do table.insert(out, v) end
  for _, v in ipairs(b) do table.insert(out, v) end
  return out
end

local function summarize_stderr(s)
  if not s or s == "" then return "(no stderr)" end
  s = s:gsub("\r", " "):gsub("\n", " ")
  if #s > 200 then s = s:sub(1, 200) .. "…" end
  return s
end

-- uploader.run(target, local_path, remote_dir) -> remote_path | (nil, err)
function M.run(target, local_path, remote_dir)
  remote_dir = remote_dir or "/tmp"

  -- 1) Compute content-addressed filename from sha1(file)[:8].
  local hash, err = parse.hash_filename(local_path)
  if not hash then return nil, "hash failed: " .. tostring(err) end

  local remote_path = remote_dir .. "/wezterm-paste-" .. hash .. ".png"

  -- 2) Validate the remote path against an allowlist whitelist.
  --    validate_remote_path rejects anything outside [A-Za-z0-9/_-.], so
  --    the string we pass to ssh's remote-shell command is safe to
  --    interpolate directly — no further shell quoting is needed on the
  --    remote side BECAUSE validate_remote_path has already rejected any
  --    shell metacharacter.
  local validated, perr = parse.validate_remote_path(remote_path)
  if not validated then return nil, "remote path rejected: " .. tostring(perr) end

  -- 3) ssh precheck: test -e <remote_path>.  Exit 0 → file already present.
  local precheck_argv = concat({ "ssh" }, target.replay_flags)
  precheck_argv = concat(precheck_argv, CONTROL_FLAGS)
  table.insert(precheck_argv, target.destination)
  -- Safe to interpolate `validated` directly: validate_remote_path has
  -- already guaranteed the string contains only [A-Za-z0-9/_-.].
  table.insert(precheck_argv, "test -e " .. validated)
  local pre = run.exec(precheck_argv)
  if pre.success then
    return validated  -- file already present, skip upload
  end

  -- 4) scp: copy local_path → destination:remote_path.
  local scp_argv = concat({ "scp" }, target.replay_flags)
  scp_argv = concat(scp_argv, CONTROL_FLAGS)
  table.insert(scp_argv, local_path)
  table.insert(scp_argv, target.destination .. ":" .. validated)
  local up = run.exec(scp_argv)
  if not up.success then
    return nil, summarize_stderr(up.stderr)
  end

  return validated
end

return M

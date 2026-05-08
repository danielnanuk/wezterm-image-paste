-- wezterm-image-paste/run.lua
--
-- Subprocess execution wrapper. The single trust boundary for shell-out
-- in this project; every other module routes through M.exec(argv).
--
-- Returned table shape:
--   { success: bool, exit_code: number, stdout: string, stderr: string }
--
-- IMPORTANT: when running INSIDE WezTerm, exit_code is informational only.
-- wezterm.run_child_process(argv) does not expose the real exit code, so
-- M.use_wezterm sets exit_code to 0 on success and 1 on failure regardless
-- of the actual exit value. Callers MUST branch on `success` (and read
-- `stderr` for diagnostics), not on exit_code values.
--
-- Outside WezTerm (i.e. under busted), the default _impl uses os.execute
-- + tempfile redirection and DOES surface the real exit code.

local M = {}

-- posix_shell_quote: wraps a string in single quotes with correct escaping.
-- POSIX: single-quote everything, replace ' with '"'"'.
-- This is the correct approach for arbitrary shell arguments, unlike Lua's
-- string.format("%q") which produces Lua string literals, not POSIX shell
-- quoting. The upstream trust boundary for path arguments is
-- validate_remote_path in parse.lua, but we quote correctly here as
-- belt-and-suspenders regardless of input source.
local function posix_shell_quote(s)
  return "'" .. s:gsub("'", [['"'"']]) .. "'"
end

-- Default impl uses io.popen for tests run outside WezTerm. Inside WezTerm
-- this module is shimmed by init.lua to wrap wezterm.run_child_process so
-- we can also capture stderr. Tests can replace M._impl directly.
M._impl = function(argv)
  -- Build a POSIX shell-quoted command. argv is a list of strings.
  local quoted = {}
  for _, a in ipairs(argv) do
    table.insert(quoted, posix_shell_quote(a))
  end
  -- Capture stdout and stderr separately via tempfiles.
  local out_t = os.tmpname()
  local err_t = os.tmpname()
  local cmd = table.concat(quoted, " ")
    .. " >" .. posix_shell_quote(out_t)
    .. " 2>" .. posix_shell_quote(err_t)
  local ok, _, code = os.execute(cmd)
  -- Lua 5.1: os.execute returns numeric code. Lua 5.3+: returns ok, type, code.
  if type(ok) == "number" then code = ok; ok = (code == 0) end
  local function slurp(p)
    local fh = io.open(p, "rb")
    if not fh then return "" end
    local s = fh:read("*a") or ""
    fh:close()
    return s
  end
  local stdout = slurp(out_t)
  local stderr = slurp(err_t)
  os.remove(out_t)
  os.remove(err_t)
  return {
    success = (ok == true) or (code == 0),
    exit_code = code or 0,
    stdout = stdout,
    stderr = stderr,
  }
end

function M.exec(argv)
  return M._impl(argv)
end

-- Called from init.lua at WezTerm load time to swap _impl for a wezterm-aware
-- implementation. See init.lua.
function M.use_wezterm(wezterm)
  M._impl = function(argv)
    local ok, stdout, stderr = wezterm.run_child_process(argv)
    return {
      success = ok,
      exit_code = ok and 0 or 1,
      stdout = stdout or "",
      stderr = stderr or "",
    }
  end
end

return M

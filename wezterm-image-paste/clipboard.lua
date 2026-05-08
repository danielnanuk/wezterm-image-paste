local run = require("wezterm-image-paste.run")

local M = {}

-- Returns a table:
--   { kind = "image",            local_path = "<path>" }
--   { kind = "text" }
--   { kind = "empty" }
--   { kind = "missing_pngpaste", stderr = "<text>" }
--   { kind = "probe_failed",     stderr = "<text>" }
function M.probe()
  local info = run.exec({ "osascript", "-e", "clipboard info" })
  if not info.success then
    return { kind = "probe_failed", stderr = info.stderr }
  end
  local out = info.stdout or ""
  if out == "" then return { kind = "empty" } end
  if not out:match("\xc2\xab" .. "class PNGf" .. "\xc2\xbb")
    and not out:match("\xc2\xab" .. "class TIFF" .. "\xc2\xbb") then
    return { kind = "text" }
  end
  -- Image present. Generate a guaranteed-unique tempfile path.
  -- os.tmpname() returns an OS-unique path under TMPDIR (e.g. /tmp/lua_XXXXXX).
  -- We append .png because pngpaste cares about the suffix.
  -- A side effect: os.tmpname() on glibc actually creates the (empty) file at
  -- the bare path; that file is harmless, will be overwritten by pngpaste at
  -- the .png path, and macOS reaps both via its TMPDIR sweep policy.
  local local_path = os.tmpname() .. ".png"
  local r = run.exec({ "pngpaste", local_path })
  if not r.success then
    return { kind = "missing_pngpaste", stderr = r.stderr }
  end
  return { kind = "image", local_path = local_path }
end

function M.write(text)
  -- printf %s avoids any trailing newline that would press Return on next paste.
  return run.exec({ "sh", "-c", 'printf %s "$1" | pbcopy', "_", text })
end

-- Save current clipboard PNG to an explicit path (used by non-SSH-pane fallback).
function M.save_to(local_path)
  return run.exec({ "pngpaste", local_path })
end

return M

local run = require("wezterm-image-paste.run")

local M = {}

-- Returns a table:
--   { kind = "image",            local_path = "<path>" }
--   { kind = "text" }
--   { kind = "empty" }
--   { kind = "missing_pngpaste", stderr = "<message>" }
function M.probe()
  local info = run.exec({ "osascript", "-e", "clipboard info" })
  if not info.success then return { kind = "empty" } end
  local out = info.stdout or ""
  if out == "" then return { kind = "empty" } end
  if not out:match("\xc2\xab" .. "class PNGf" .. "\xc2\xbb")
    and not out:match("\xc2\xab" .. "class TIFF" .. "\xc2\xbb") then
    return { kind = "text" }
  end
  -- Image present. Try pngpaste.
  local tmpdir = os.getenv("TMPDIR") or "/tmp"
  -- Use a unique name to allow concurrent pastes.
  local local_path = string.format("%swezterm-paste-%d-%d.png",
    tmpdir:sub(-1) == "/" and tmpdir or (tmpdir .. "/"),
    os.time(), math.random(100000, 999999))
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

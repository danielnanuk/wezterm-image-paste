local clipboard = require("wezterm-image-paste.clipboard")
local ssh_target = require("wezterm-image-paste.ssh_target")
local uploader = require("wezterm-image-paste.uploader")
local notify = require("wezterm-image-paste.notify")

local M = {}

local DEFAULTS = {
  remote_dir = "/tmp",
  local_fallback_dir = (os.getenv("HOME") or "/tmp") .. "/Downloads",
  timeout_seconds = 10,
}

-- Returns one of:
--   { outcome = "uploaded",          remote_path = ... }
--   { outcome = "fallback_local",    local_path = ... }   -- added in Task 14
--   { outcome = "passthrough" }      -- text/empty clipboard, native paste runs
--   { outcome = "missing_pngpaste" }
--   { outcome = "probe_failed",      err = ... }
--   { outcome = "ssh_fail",          err = ... }
--   { outcome = "non_ssh_image" }    -- handled inside via fallback (Task 14)
function M.handle_paste(window, pane, opts)
  opts = opts or {}
  local remote_dir = opts.remote_dir or DEFAULTS.remote_dir

  local probe = clipboard.probe()

  if probe.kind == "text" or probe.kind == "empty" then
    return { outcome = "passthrough" }
  end
  if probe.kind == "probe_failed" then
    notify.toast(window, "✗ 剪贴板探测失败: " .. tostring(probe.stderr or ""), "error")
    return { outcome = "probe_failed", err = probe.stderr }
  end
  if probe.kind == "missing_pngpaste" then
    notify.toast(window, "❗需要 brew install pngpaste,本次未上传", "error")
    return { outcome = "missing_pngpaste" }
  end
  -- probe.kind == "image"

  local target = ssh_target.detect_from_pane(pane)
  if not target then
    local fallback_dir = opts.local_fallback_dir or DEFAULTS.local_fallback_dir
    local stamp = os.date("!%Y%m%dT%H%M%SZ")
    local local_path = fallback_dir .. "/wezterm-paste-" .. stamp .. ".png"
    -- Ensure dir exists. mkdir -p is safe and idempotent.
    require("wezterm-image-paste.run").exec({ "mkdir", "-p", fallback_dir })
    local r = clipboard.save_to(local_path)
    if not r.success then
      notify.toast(window, "✗ 保存到本地失败: " .. (r.stderr or ""), "error")
      return { outcome = "ssh_fail", err = r.stderr }
    end
    clipboard.write(local_path)
    notify.toast(window, "📎 非 SSH 会话,图片已存到 " .. fallback_dir .. ",路径已复制", "info")
    return { outcome = "fallback_local", local_path = local_path }
  end

  local remote_path, err = uploader.run(target, probe.local_path, remote_dir)
  if not remote_path then
    notify.toast(window, "✗ 上传失败: " .. tostring(err), "error")
    return { outcome = "ssh_fail", err = err }
  end

  clipboard.write(remote_path)
  notify.toast(window, "📎 路径已复制到剪贴板,Cmd+V 即可粘贴", "info")
  return { outcome = "uploaded", remote_path = remote_path }
end

return M

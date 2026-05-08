-- wezterm-image-paste: paste local clipboard images into remote SSH sessions
-- as scp-uploaded file paths. See docs/superpowers/specs/2026-05-08-...
local M = {}
M.VERSION = "0.1.0"

local DEFAULT_OPTS = {
  bind_cmd_v = true,
  remote_dir = "/tmp",
  local_fallback_dir = (os.getenv("HOME") or "/tmp") .. "/Downloads",
  timeout_seconds = 10,
}

local function merge(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over or {}) do out[k] = v end
  return out
end

function M.apply_to_config(config, user_opts)
  local wezterm = require("wezterm")
  local run = require("wezterm-image-paste.run")
  local notify = require("wezterm-image-paste.notify")
  local handler = require("wezterm-image-paste.handler")

  run.use_wezterm(wezterm)
  notify.use_wezterm(wezterm)

  local opts = merge(DEFAULT_OPTS, user_opts)

  if not opts.bind_cmd_v then return end

  local act = wezterm.action

  config.keys = config.keys or {}
  table.insert(config.keys, {
    key = "v",
    mods = "CMD",
    action = wezterm.action_callback(function(window, pane)
      local r = handler.handle_paste(window, pane, opts)
      if r.outcome == "passthrough" then
        window:perform_action(act.PasteFrom("Clipboard"), pane)
      end
      -- Outcomes other than "passthrough" all skip native paste, because:
      --   uploaded / fallback_local: clipboard now holds a remote/local path;
      --                              user pastes the path manually.
      --   missing_pngpaste / probe_failed / ssh_fail / fallback_failed:
      --                              clipboard still holds the original image;
      --                              native paste would dump PNG bytes into
      --                              the terminal stream.
    end),
  })
end

return M

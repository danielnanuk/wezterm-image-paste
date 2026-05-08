local M = {}

-- These two are set by init.use_wezterm at load time, so tests can stub them.
M._toast_impl = function(window, msg, level) end
M._log_impl = function(level, msg) end

function M.toast(window, msg, level)
  pcall(M._toast_impl, window, msg, level)
end

function M.log(level, msg)
  pcall(M._log_impl, level, msg)
end

function M.use_wezterm(wezterm)
  M._toast_impl = function(window, msg, level)
    if window and window.toast_notification then
      -- Errors and warnings get more time on screen so users can read them.
      local duration = (level == "error" or level == "warn") and 6000 or 4000
      window:toast_notification("wezterm-image-paste", msg, nil, duration)
    end
  end
  M._log_impl = function(level, msg)
    if level == "error" then
      wezterm.log_error(msg)
    elseif level == "warn" then
      wezterm.log_warn(msg)
    else
      wezterm.log_info(msg)
    end
  end
end

return M

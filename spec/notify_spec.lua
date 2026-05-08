local notify = require("wezterm-image-paste.notify")

describe("notify", function()
  it("toast is callable", function()
    assert.is_function(notify.toast)
  end)

  it("log is callable", function()
    assert.is_function(notify.log)
  end)

  it("toast pcall swallows errors from _impl stub", function()
    notify._toast_impl = function()
      error("test error")
    end
    -- Should not raise
    assert.has_no.errors(function()
      notify.toast(nil, "test", "info")
    end)
  end)

  it("log pcall swallows errors from _impl stub", function()
    notify._log_impl = function()
      error("test error")
    end
    -- Should not raise
    assert.has_no.errors(function()
      notify.log("info", "test")
    end)
  end)

  describe("use_wezterm", function()
    it("replaces _toast_impl and _log_impl with wezterm-aware versions", function()
      local fake_wezterm = {
        log_error = function() end,
        log_warn = function() end,
        log_info = function() end,
      }

      notify.use_wezterm(fake_wezterm)

      -- After use_wezterm, the impls should be different from the empty ones
      assert.is_function(notify._toast_impl)
      assert.is_function(notify._log_impl)

      -- They should exist and be callable (verifying they were assigned)
      assert.has_no.errors(function()
        notify._toast_impl(nil, "test", "info")
        notify._log_impl("info", "test")
      end)
    end)

    it("toast calls window:toast_notification when window has the method", function()
      local toast_called = false
      local fake_window = {
        toast_notification = function(self, title, msg, _, duration)
          toast_called = true
          assert.are.equal("wezterm-image-paste", title)
          assert.are.equal("test message", msg)
          assert.are.equal(4000, duration)
        end,
      }

      local fake_wezterm = {
        log_error = function() end,
        log_warn = function() end,
        log_info = function() end,
      }

      notify.use_wezterm(fake_wezterm)
      notify.toast(fake_window, "test message", "info")

      assert.is_true(toast_called)
    end)

    it("log calls appropriate wezterm.log_* based on level", function()
      local calls = { error = 0, warn = 0, info = 0 }
      local fake_wezterm = {
        log_error = function()
          calls.error = calls.error + 1
        end,
        log_warn = function()
          calls.warn = calls.warn + 1
        end,
        log_info = function()
          calls.info = calls.info + 1
        end,
      }

      notify.use_wezterm(fake_wezterm)

      notify.log("error", "err msg")
      assert.are.equal(1, calls.error)

      notify.log("warn", "warn msg")
      assert.are.equal(1, calls.warn)

      notify.log("info", "info msg")
      assert.are.equal(1, calls.info)
    end)
  end)
end)

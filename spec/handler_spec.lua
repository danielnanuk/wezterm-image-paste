local handler = require("wezterm-image-paste.handler")
local clipboard = require("wezterm-image-paste.clipboard")
local ssh_target = require("wezterm-image-paste.ssh_target")
local uploader = require("wezterm-image-paste.uploader")
local notify = require("wezterm-image-paste.notify")

-- Helper: stub the four collaborators on a per-test basis.
local function stub_all(over)
  local saved = {
    probe = clipboard.probe,
    write = clipboard.write,
    detect = ssh_target.detect_from_pane,
    upload = uploader.run,
    save_to = clipboard.save_to,
    toast = notify._toast_impl,
    log = notify._log_impl,
  }
  clipboard.probe       = over.probe       or saved.probe
  clipboard.write       = over.write       or saved.write
  clipboard.save_to     = over.save_to     or saved.save_to
  ssh_target.detect_from_pane = over.detect or saved.detect
  uploader.run          = over.upload      or saved.upload
  notify._toast_impl    = over.toast       or function() end
  notify._log_impl      = over.log         or function() end
  return saved
end

local function restore(saved)
  clipboard.probe = saved.probe
  clipboard.write = saved.write
  clipboard.save_to = saved.save_to
  ssh_target.detect_from_pane = saved.detect
  uploader.run = saved.upload
  notify._toast_impl = saved.toast
  notify._log_impl = saved.log
end

describe("handler.handle_paste (happy path)", function()
  local saved

  after_each(function()
    if saved then restore(saved); saved = nil end
  end)

  it("upload + clipboard rewrite when image + ssh pane", function()
    local written, toasted
    saved = stub_all({
      probe = function() return { kind = "image", local_path = "/tmp/x.png" } end,
      detect = function() return { destination = "root@host", replay_flags = {} } end,
      upload = function(target, local_path, remote_dir)
        return "/tmp/wezterm-paste-aaaaaaaa.png"
      end,
      write = function(text) written = text end,
      toast = function(_, msg) toasted = msg end,
    })

    local result = handler.handle_paste({}, {}, { remote_dir = "/tmp" })

    assert.are.equal("uploaded", result.outcome)
    assert.are.equal("/tmp/wezterm-paste-aaaaaaaa.png", written)
    assert.is_not_nil(toasted)
    assert.is_truthy(toasted:find("📎"))
  end)
end)

describe("handler.handle_paste (passthrough)", function()
  local saved

  after_each(function()
    if saved then restore(saved); saved = nil end
  end)

  it("returns passthrough for text clipboard", function()
    saved = stub_all({
      probe = function() return { kind = "text" } end,
    })
    local r = handler.handle_paste({}, {}, {})
    assert.are.equal("passthrough", r.outcome)
  end)

  it("returns passthrough for empty clipboard", function()
    saved = stub_all({
      probe = function() return { kind = "empty" } end,
    })
    local r = handler.handle_paste({}, {}, {})
    assert.are.equal("passthrough", r.outcome)
  end)
end)

describe("handler.handle_paste (non-ssh image fallback)", function()
  local saved
  after_each(function() if saved then restore(saved); saved = nil end end)

  it("saves image to local fallback dir and rewrites clipboard with that path", function()
    local saved_to, written, toasted
    saved = stub_all({
      probe = function() return { kind = "image", local_path = "/tmp/x.png" } end,
      detect = function() return nil end,        -- NOT ssh
      save_to = function(p) saved_to = p
        return { success = true, exit_code = 0, stdout = "", stderr = "" } end,
      write = function(t) written = t end,
      toast = function(_, msg) toasted = msg end,
    })
    local r = handler.handle_paste({}, {}, { local_fallback_dir = "/tmp/fallback" })
    assert.are.equal("fallback_local", r.outcome)
    assert.is_truthy(saved_to:match("^/tmp/fallback/wezterm%-paste%-.+%.png$"))
    assert.are.equal(saved_to, written)
    assert.is_truthy(toasted and toasted:find("📎"))
  end)

  it("returns fallback_failed outcome when save_to fails", function()
    local toasted, toast_level
    saved = stub_all({
      probe = function() return { kind = "image", local_path = "/tmp/x.png" } end,
      detect = function() return nil end,        -- NOT ssh
      save_to = function(_p)
        return { success = false, exit_code = 1, stdout = "", stderr = "disk full" } end,
      toast = function(_, msg, level) toasted = msg; toast_level = level end,
    })
    local r = handler.handle_paste({}, {}, { local_fallback_dir = "/tmp/fallback" })
    assert.are.equal("fallback_failed", r.outcome)
    assert.are.equal("disk full", r.err)
    assert.are.equal("error", toast_level)
  end)
end)

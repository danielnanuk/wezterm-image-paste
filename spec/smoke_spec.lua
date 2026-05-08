describe("project skeleton", function()
  it("can require the entry module", function()
    package.path = package.path .. ";./?/init.lua;./?.lua"
    local mod = require("wezterm-image-paste")
    assert.are.equal("0.1.0", mod.VERSION)
  end)
end)

describe("init.apply_to_config (no wezterm available)", function()
  it("raises a clear error when require('wezterm') fails", function()
    local mod = require("wezterm-image-paste")
    -- Loading busted runtime; require('wezterm') should fail.
    local ok, err = pcall(mod.apply_to_config, {}, {})
    assert.is_false(ok)
    assert.is_truthy(tostring(err):match("wezterm"))
  end)
end)

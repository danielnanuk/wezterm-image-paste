describe("project skeleton", function()
  it("can require the entry module", function()
    package.path = package.path .. ";./?/init.lua;./?.lua"
    local mod = require("wezterm-image-paste")
    assert.are.equal("0.1.0", mod.VERSION)
  end)
end)

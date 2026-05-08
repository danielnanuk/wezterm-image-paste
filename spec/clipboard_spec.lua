local clipboard = require("wezterm-image-paste.clipboard")
local run = require("wezterm-image-paste.run")

describe("clipboard.probe", function()
  local saved
  before_each(function() saved = run._impl end)
  after_each(function() run._impl = saved end)

  it("returns kind=image when osascript reports PNGf and pngpaste succeeds", function()
    run._impl = function(argv)
      if argv[1] == "osascript" then
        return { success = true, exit_code = 0, stdout = "«class PNGf», «class TEXT»", stderr = "" }
      end
      if argv[1] == "pngpaste" then
        return { success = true, exit_code = 0, stdout = "", stderr = "" }
      end
      error("unexpected argv: " .. argv[1])
    end
    local r = clipboard.probe()
    assert.are.equal("image", r.kind)
    assert.is_string(r.local_path)
  end)

  it("returns kind=text when there is no PNGf", function()
    run._impl = function(argv)
      if argv[1] == "osascript" then
        return { success = true, exit_code = 0, stdout = "«class TEXT»", stderr = "" }
      end
      error("did not expect: " .. argv[1])
    end
    assert.are.equal("text", clipboard.probe().kind)
  end)

  it("returns kind=empty when osascript output is empty", function()
    run._impl = function() return { success = true, exit_code = 0, stdout = "", stderr = "" } end
    assert.are.equal("empty", clipboard.probe().kind)
  end)

  it("returns kind=missing_pngpaste when pngpaste is unavailable", function()
    run._impl = function(argv)
      if argv[1] == "osascript" then
        return { success = true, exit_code = 0, stdout = "«class PNGf»", stderr = "" }
      end
      if argv[1] == "pngpaste" then
        return { success = false, exit_code = 127, stdout = "", stderr = "command not found" }
      end
    end
    assert.are.equal("missing_pngpaste", clipboard.probe().kind)
  end)
end)

describe("clipboard.write", function()
  it("pipes text into pbcopy without trailing newline", function()
    local captured
    run._impl = function(argv)
      captured = argv
      return { success = true, exit_code = 0, stdout = "", stderr = "" }
    end
    clipboard.write("/tmp/wezterm-paste-a3f29c1d.png")
    -- argv must be sh -c 'printf %s "$1" | pbcopy' _ <text>
    assert.are.equal("sh", captured[1])
    assert.are.equal("-c", captured[2])
    assert.is_truthy(captured[3]:match("printf"))
    assert.is_truthy(captured[3]:match("pbcopy"))
    assert.are.equal("/tmp/wezterm-paste-a3f29c1d.png", captured[5])
  end)
end)

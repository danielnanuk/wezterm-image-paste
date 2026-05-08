local run = require("wezterm-image-paste.run")

describe("run.exec", function()
  it("returns success/exit/stdout/stderr table from real /usr/bin/true", function()
    local r = run.exec({ "/usr/bin/true" })
    assert.is_true(r.success)
    assert.are.equal(0, r.exit_code)
    assert.are.equal("", r.stdout)
  end)

  it("captures stderr from a failing command", function()
    local r = run.exec({ "/bin/sh", "-c", "echo oops 1>&2; exit 7" })
    assert.is_false(r.success)
    assert.are.equal(7, r.exit_code)
    assert.is_truthy(r.stderr:match("oops"))
  end)

  it("can be replaced via the _impl injection point", function()
    local original = run._impl
    run._impl = function(argv)
      return { success = true, exit_code = 0, stdout = "fake", stderr = "" }
    end
    local r = run.exec({ "anything" })
    assert.are.equal("fake", r.stdout)
    run._impl = original
  end)
end)

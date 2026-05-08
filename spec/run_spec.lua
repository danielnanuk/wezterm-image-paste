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

  it("does not shell-inject through hostile argv", function()
    -- If posix_shell_quote regresses to string.format('%q', ...) or
    -- naive concatenation, this test will execute /bin/false (or worse)
    -- and we'll see the command fail (r.success == false).
    local hostile = "a';/bin/false;echo HACKED;'"
    local r = run.exec({ "/bin/sh", "-c", "printf '[%s]' \"$1\"", "_", hostile })
    assert.is_true(r.success, "shell command must succeed: stderr=" .. (r.stderr or ""))
    assert.are.equal("[" .. hostile .. "]", r.stdout)
  end)
end)

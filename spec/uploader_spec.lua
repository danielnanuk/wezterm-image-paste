local uploader = require("wezterm-image-paste.uploader")
local run = require("wezterm-image-paste.run")
local parse = require("wezterm-image-paste.parse")

local target = {
  destination = "root@47.237.21.3",
  replay_flags = {
    "-J", "root@8.210.34.23",
    "-o", "ServerAliveInterval=30",
  },
}

describe("uploader.run", function()
  local saved
  before_each(function() saved = run._impl end)
  after_each(function() run._impl = saved end)

  it("calls ssh test -e with replay_flags + ControlMaster, then scp on miss", function()
    local calls = {}
    run._impl = function(argv)
      table.insert(calls, argv)
      if argv[1] == "ssh" then
        return { success = false, exit_code = 1, stdout = "", stderr = "" }
      end
      if argv[1] == "scp" then
        return { success = true, exit_code = 0, stdout = "", stderr = "" }
      end
    end

    local rp, err = uploader.run(target, "spec/fixtures/hello.bin", "/tmp")
    assert.is_nil(err)
    assert.is_truthy(rp:match("^/tmp/wezterm%-paste%-[0-9a-f]+%.png$"))

    -- Inspect ssh precheck argv
    local ssh_call = calls[1]
    assert.are.equal("ssh", ssh_call[1])
    -- replay_flags must appear in order, before ControlMaster flags
    local flat = table.concat(ssh_call, " ")
    assert.is_truthy(flat:match("%-J root@8%.210%.34%.23"))
    assert.is_truthy(flat:match("ServerAliveInterval=30"))
    assert.is_truthy(flat:match("ControlMaster=auto"))
    assert.is_truthy(flat:match("test %-e /tmp/wezterm%-paste%-"))

    -- Inspect scp argv: replay_flags must appear in order before ControlMaster flags
    local scp_call = calls[2]
    assert.are.equal("scp", scp_call[1])
    flat = table.concat(scp_call, " ")
    assert.is_truthy(flat:match("%-J root@8%.210%.34%.23"))
    assert.is_truthy(flat:match("ControlMaster=auto"))
    assert.is_truthy(flat:match("root@47%.237%.21%.3:/tmp/wezterm%-paste%-"))

    -- Verify replay_flags appear before ControlMaster in both calls (order check)
    local function find_pos(tbl, val)
      for idx, v in ipairs(tbl) do
        if v == val then return idx end
      end
      return nil
    end
    local ssh_J_pos = find_pos(ssh_call, "-J")
    local ssh_cm_pos = find_pos(ssh_call, "ControlMaster=auto")
    assert.is_truthy(ssh_J_pos < ssh_cm_pos, "replay_flags must precede ControlMaster in ssh call")

    local scp_J_pos = find_pos(scp_call, "-J")
    local scp_cm_pos = find_pos(scp_call, "ControlMaster=auto")
    assert.is_truthy(scp_J_pos < scp_cm_pos, "replay_flags must precede ControlMaster in scp call")
  end)

  it("skips scp when precheck succeeds (file already present)", function()
    local calls = {}
    run._impl = function(argv)
      table.insert(calls, argv[1])
      if argv[1] == "ssh" then
        return { success = true, exit_code = 0, stdout = "", stderr = "" }
      end
      error("scp should not have been called")
    end
    local rp, err = uploader.run(target, "spec/fixtures/hello.bin", "/tmp")
    assert.is_nil(err)
    assert.is_string(rp)
    assert.are.same({ "ssh" }, calls)
  end)

  it("returns nil + error summary when scp fails", function()
    run._impl = function(argv)
      if argv[1] == "ssh" then
        return { success = false, exit_code = 1, stdout = "", stderr = "" }
      end
      if argv[1] == "scp" then
        return { success = false, exit_code = 1, stdout = "",
                 stderr = "ssh: connect to host 47.237.21.3 port 22: Network is unreachable" }
      end
    end
    local rp, err = uploader.run(target, "spec/fixtures/hello.bin", "/tmp")
    assert.is_nil(rp)
    assert.is_string(err)
    assert.is_truthy(err:match("Network is unreachable"))
  end)

  it("returns nil + error if hash_filename fails", function()
    local rp, err = uploader.run(target, "/nonexistent/file", "/tmp")
    assert.is_nil(rp)
    assert.is_string(err)
  end)

  it("returns nil + error if remote_dir contains shell metacharacters", function()
    local rp, err = uploader.run(target, "spec/fixtures/hello.bin", "/tmp/foo;rm")
    assert.is_nil(rp)
    assert.is_truthy(err:match("remote path rejected"))
  end)
end)

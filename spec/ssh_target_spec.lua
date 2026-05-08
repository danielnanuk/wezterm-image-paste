local ssh_target = require("wezterm-image-paste.ssh_target")

local function proc(name, argv, children)
  return { name = name, argv = argv, children = children or {} }
end

describe("ssh_target.detect", function()
  it("finds ssh as a direct child", function()
    local tree = proc("zsh", { "zsh" }, {
      proc("ssh", { "ssh", "host" }),
    })
    local r = ssh_target.detect(tree)
    assert.are.same({ destination = "host", replay_flags = {} }, r)
  end)

  it("finds ssh nested under tmux/Claude/etc.", function()
    local tree = proc("zsh", { "zsh" }, {
      proc("ssh", { "ssh", "-J", "j", "user@host" }, {
        proc("tmux", { "tmux" }, {
          proc("claude", { "claude" }),
        }),
      }),
    })
    local r = ssh_target.detect(tree)
    assert.are.same({
      destination = "user@host",
      replay_flags = { "-J", "j" },
    }, r)
  end)

  it("returns nil when there is no ssh in the tree", function()
    local tree = proc("zsh", { "zsh" }, {
      proc("vim", { "vim" }),
    })
    assert.is_nil(ssh_target.detect(tree))
  end)

  it("does not match ssh-add or sshfs", function()
    local tree = proc("zsh", { "zsh" }, {
      proc("ssh-add", { "ssh-add" }),
      proc("sshfs", { "sshfs", "host:/", "/mnt" }),
    })
    assert.is_nil(ssh_target.detect(tree))
  end)

  it("returns nil if proc info is nil", function()
    assert.is_nil(ssh_target.detect(nil))
  end)

  -- Proactive test 1: ssh nested deeper than two levels (tmux inside tmux)
  it("finds ssh nested three or more levels deep", function()
    local tree = proc("zsh", { "zsh" }, {
      proc("tmux", { "tmux" }, {
        proc("tmux", { "tmux" }, {
          proc("ssh", { "ssh", "deep-host" }),
        }),
      }),
    })
    local r = ssh_target.detect(tree)
    assert.are.same({ destination = "deep-host", replay_flags = {} }, r)
  end)

  -- Proactive test 2: name is "ssh" but argv[1] is a full path like /usr/bin/ssh
  it("works when argv[1] is a full path to ssh", function()
    local tree = proc("ssh", { "/usr/bin/ssh", "host" })
    local r = ssh_target.detect(tree)
    assert.are.same({ destination = "host", replay_flags = {} }, r)
  end)
end)

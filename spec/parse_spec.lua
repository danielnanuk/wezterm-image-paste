local parse = require("wezterm-image-paste.parse")

describe("parse.hash_filename", function()
  it("returns an 8-char lowercase hex string", function()
    local h = parse.hash_filename("spec/fixtures/hello.bin")
    assert.is_string(h)
    assert.are.equal(8, #h)
    assert.is_truthy(h:match("^[0-9a-f]+$"))
  end)

  it("is deterministic for the same content", function()
    local h1 = parse.hash_filename("spec/fixtures/hello.bin")
    local h2 = parse.hash_filename("spec/fixtures/hello.bin")
    assert.are.equal(h1, h2)
  end)

  it("differs for different content", function()
    local h1 = parse.hash_filename("spec/fixtures/hello.bin")
    local h2 = parse.hash_filename("spec/fixtures/empty.bin")
    assert.are_not.equal(h1, h2)
  end)

  it("returns nil for missing file", function()
    local h, err = parse.hash_filename("spec/fixtures/does-not-exist.bin")
    assert.is_nil(h)
    assert.is_string(err)
  end)
end)

describe("parse.parse_ssh_argv (basic)", function()
  it("ssh host", function()
    local r = parse.parse_ssh_argv({ "ssh", "host" })
    assert.are.same({ destination = "host", replay_flags = {} }, r)
  end)

  it("ssh user@host", function()
    local r = parse.parse_ssh_argv({ "ssh", "user@host" })
    assert.are.same({ destination = "user@host", replay_flags = {} }, r)
  end)

  it("ssh -- host", function()
    local r = parse.parse_ssh_argv({ "ssh", "--", "host" })
    assert.are.same({ destination = "host", replay_flags = {} }, r)
  end)

  it("returns nil for empty argv", function()
    assert.is_nil(parse.parse_ssh_argv({}))
  end)

  it("returns nil if argv[1] is not 'ssh' (basename match)", function()
    assert.is_nil(parse.parse_ssh_argv({ "ssh-add" }))
    assert.is_nil(parse.parse_ssh_argv({ "sshfs", "host:/", "/mnt" }))
  end)

  it("accepts a full path basename like /usr/bin/ssh", function()
    local r = parse.parse_ssh_argv({ "/usr/bin/ssh", "host" })
    assert.are.same({ destination = "host", replay_flags = {} }, r)
  end)
end)

describe("parse.parse_ssh_argv (arg-consuming flags)", function()
  it("ssh -p 22 user@host", function()
    local r = parse.parse_ssh_argv({ "ssh", "-p", "22", "user@host" })
    assert.are.same(
      { destination = "user@host", replay_flags = { "-p", "22" } },
      r
    )
  end)

  it("ssh -i ~/.ssh/id_ed25519 host cmd (cmd is remote command, not in replay)", function()
    local r = parse.parse_ssh_argv({ "ssh", "-i", "~/.ssh/id_ed25519", "host", "cmd" })
    assert.are.same(
      { destination = "host", replay_flags = { "-i", "~/.ssh/id_ed25519" } },
      r
    )
  end)

  it("ssh -J jump host", function()
    local r = parse.parse_ssh_argv({ "ssh", "-J", "jump", "host" })
    assert.are.same(
      { destination = "host", replay_flags = { "-J", "jump" } },
      r
    )
  end)

  it("the canonical complex case from the spec", function()
    local argv = {
      "ssh",
      "-J", "root@8.210.34.23",
      "-o", "ServerAliveInterval=30",
      "-o", "ServerAliveCountMax=3",
      "root@47.237.21.3",
    }
    local r = parse.parse_ssh_argv(argv)
    assert.are.same({
      destination = "root@47.237.21.3",
      replay_flags = {
        "-J", "root@8.210.34.23",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
      },
    }, r)
  end)

  it("returns nil if a required arg is missing", function()
    assert.is_nil(parse.parse_ssh_argv({ "ssh", "-p" }))
  end)
end)

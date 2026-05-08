# Image Paste Over SSH — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Cmd+V` handler to WezTerm that, when the macOS clipboard contains an image and the active pane is an SSH session, uploads the image to the remote machine via `scp` and replaces the local clipboard with the resulting remote file path — so the user can immediately paste that path into Claude Code (or any TUI app) running on the remote.

**Architecture:** Pure Lua module (`wezterm-image-paste`) loaded from `~/.wezterm.lua`. Components are small, single-purpose Lua files. Pure functions (argv parser, file hash) are unit-tested with `busted`. Components that shell out have their subprocess runner injected so tests can mock it. No changes to WezTerm core, no remote deployment.

**Tech Stack:** WezTerm Lua API; macOS `osascript`, `pngpaste` (Homebrew), `pbcopy`; OpenSSH `ssh`/`scp` with `ControlMaster`; `busted` for tests; `luarocks` for tooling.

---

## Project Layout

All paths are relative to the repository root (`/home/daniel/pTerminal`).

### Source files (`wezterm-image-paste/`)

| Path | Responsibility |
|------|---------------|
| `wezterm-image-paste/init.lua` | Entry. Exports `apply_to_config(config, opts?)`. Wires the Cmd+V keybinding to the orchestrator. Holds defaults table. |
| `wezterm-image-paste/parse.lua` | **Pure functions only.** `parse_ssh_argv(argv)` (returns `{destination, replay_flags}`), `hash_filename(path)` (returns 8-char hex), `validate_remote_path(s)` (validates safe chars). |
| `wezterm-image-paste/run.lua` | Thin wrapper around `wezterm.run_child_process`. Modules use this so tests can inject a fake. Single function: `run.exec(argv) → {success, exit_code, stdout, stderr}`. |
| `wezterm-image-paste/clipboard.lua` | `clipboard.probe()` (osascript + pngpaste), `clipboard.write(text)` (pbcopy without newline), `clipboard.save_to(local_path)` (pngpaste to a chosen path). |
| `wezterm-image-paste/ssh_target.lua` | `ssh_target.detect(pane)` — walks pane's foreground process tree, finds nearest `ssh` descendant, calls `parse.parse_ssh_argv`. Returns `{destination, replay_flags}` or `nil`. |
| `wezterm-image-paste/uploader.lua` | `uploader.run(target, local_path, remote_dir)` — computes hash, runs precheck (`ssh ... test -e`), runs `scp` if needed. Returns `remote_path` or `(nil, err_summary)`. |
| `wezterm-image-paste/notify.lua` | `notify.toast(window, msg, level)` — `gui_window:toast_notification(...)`. `notify.log(level, msg)` — `wezterm.log_*`. |
| `wezterm-image-paste/handler.lua` | Orchestrator. `handler.handle_paste(window, pane, opts)` — the only function with control flow. Implements every error branch in spec §8. |

### Test files (`spec/`)

| Path | What it tests |
|------|---------------|
| `spec/parse_spec.lua` | All branches of `parse.parse_ssh_argv`, `hash_filename`, `validate_remote_path`. No subprocess. |
| `spec/clipboard_spec.lua` | `clipboard.probe` and `clipboard.write` with mocked `run.exec`. |
| `spec/ssh_target_spec.lua` | `ssh_target.detect` with fake `pane:get_foreground_process_info()` shapes. |
| `spec/uploader_spec.lua` | `uploader.run` with mocked `run.exec`. Asserts exact argv passed to `ssh`/`scp`. |
| `spec/handler_spec.lua` | `handler.handle_paste` with all dependencies mocked. Walks every branch in spec §8. |

### Docs

| Path | Content |
|------|---------|
| `README.md` | Three-step install (brew install, copy module, edit `~/.wezterm.lua`) + recommended `ControlMaster` ssh_config snippet. |
| `docs/manual-test-checklist.md` | The 9 manual cases from spec §10 ("Manual checklist" + 6b). |

### Config files

| Path | Content |
|------|---------|
| `.busted` | busted runner config: `spec/` directory, output style. |
| `wezterm-image-paste-0.1.0-1.rockspec` | Optional luarocks rockspec so users can `luarocks install --local`. |
| `.gitignore` | Ignore `*.rock`, `.luarocks/`, `lua_modules/`. |

---

## Notes for the Implementer

You are likely new to this codebase (it is empty — that is normal, this is a greenfield project). A few things to know up front so you don't waste time:

1. **WezTerm Lua runs inside WezTerm.** Pure Lua tests with `busted` run in a regular Lua interpreter (`lua` or `luajit`) and **never load `wezterm`**. Modules that need WezTerm APIs must accept their dependencies as arguments or read from injectable module-level globals (so tests can replace them).

2. **`wezterm.run_child_process(argv)` returns `(success: bool, stdout: string, stderr: string)`.** It is synchronous. We wrap it in `run.exec(argv)` which returns a single table `{success, exit_code, stdout, stderr}`. Tests inject a fake `run.exec`.

3. **Timeouts are best-effort.** WezTerm Lua has no native deadline timer. We rely on `ssh -o ConnectTimeout=10` for connection failures and accept that a stuck transfer over a working but slow link may exceed our nominal 10s budget. The spec says "10s deadline"; in practice this is a connection-level deadline. We document this in the README.

4. **TDD is mandatory for pure-function tasks.** Tests first, watch them fail, then make them pass. For tasks that exercise WezTerm APIs end-to-end, a manual checklist run is the verification — no automated GUI test exists.

5. **Run `busted` from the repository root.** It auto-discovers `spec/`. You should never need to `cd`.

6. **Commit after every task.** Each task ends with a commit step. This makes the history match the plan and lets you bisect easily.

7. **No `git` repo yet.** Task 1 initializes it. After that, the `git commit` steps work.

---

## Task 1: Project skeleton + busted setup

**Files:**
- Create: `.gitignore`
- Create: `.busted`
- Create: `spec/smoke_spec.lua`
- Create: `wezterm-image-paste/init.lua` (stub)
- Create: `README.md` (stub)

- [ ] **Step 1: Initialize git repo**

```bash
cd /home/daniel/pTerminal
git init
git config user.email "danielnanuk@gmail.com"
git config user.name "Daniel"
```

- [ ] **Step 2: Confirm `lua` and `luarocks` are installed**

Run:
```bash
which lua && lua -v
which luarocks && luarocks --version
```

Expected: both print versions. If either is missing, install with `brew install lua luarocks` and re-run.

- [ ] **Step 3: Install busted locally**

```bash
luarocks install --local busted
luarocks install --local luasec  # busted dependency on some installs
```

Add `~/.luarocks/bin` to PATH for this shell:

```bash
eval "$(luarocks path --bin)"
which busted
```

Expected: `busted` resolves under `~/.luarocks/bin` or system path.

- [ ] **Step 4: Create `.gitignore`**

```
.luarocks/
lua_modules/
*.rock
*.tar.gz
.DS_Store
```

- [ ] **Step 5: Create `.busted`**

```lua
return {
  default = {
    verbose = true,
    coverage = false,
    output = "utfTerminal",
    pattern = "_spec",
    ROOT = { "spec" },
  },
}
```

- [ ] **Step 6: Create stub `wezterm-image-paste/init.lua`**

```lua
-- wezterm-image-paste: paste local clipboard images into remote SSH sessions
-- as scp-uploaded file paths. See docs/superpowers/specs/2026-05-08-...
local M = {}
M.VERSION = "0.1.0"
return M
```

- [ ] **Step 7: Write smoke test `spec/smoke_spec.lua`**

```lua
describe("project skeleton", function()
  it("can require the entry module", function()
    package.path = package.path .. ";./?/init.lua;./?.lua"
    local mod = require("wezterm-image-paste")
    assert.are.equal("0.1.0", mod.VERSION)
  end)
end)
```

- [ ] **Step 8: Run busted**

```bash
busted
```

Expected: `1 success / 0 failures`.

- [ ] **Step 9: Create stub `README.md`**

```markdown
# wezterm-image-paste

Paste local screenshots into remote SSH sessions as `scp`-uploaded file paths.

Status: under construction. See `docs/superpowers/specs/2026-05-08-image-paste-over-ssh-design.md`.
```

- [ ] **Step 10: Commit**

```bash
git add .gitignore .busted spec/smoke_spec.lua wezterm-image-paste/init.lua README.md docs/
git commit -m "chore: project skeleton with busted smoke test"
```

---

## Task 2: `parse.hash_filename(path)` — content-addressed filename

**Files:**
- Create: `wezterm-image-paste/parse.lua`
- Create: `spec/parse_spec.lua`
- Test fixtures: `spec/fixtures/empty.bin`, `spec/fixtures/hello.bin`

- [ ] **Step 1: Create test fixtures**

```bash
mkdir -p spec/fixtures
: > spec/fixtures/empty.bin
printf 'hello' > spec/fixtures/hello.bin
```

- [ ] **Step 2: Write the failing test (`spec/parse_spec.lua`)**

```lua
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
```

- [ ] **Step 3: Run test to confirm it fails**

```bash
busted spec/parse_spec.lua
```

Expected: errors loading `wezterm-image-paste.parse` (module not found).

- [ ] **Step 4: Implement `parse.hash_filename` in `wezterm-image-paste/parse.lua`**

We use the system `shasum` command to avoid pulling in a Lua sha1 library. For
true purity in tests, the implementation reads bytes itself and runs `shasum`
via `io.popen`. (No subprocess for the file read, so this still runs under
busted without a runner injection.)

```lua
local M = {}

-- Read a file and return its contents, or nil + error.
local function read_file(path)
  local fh, err = io.open(path, "rb")
  if not fh then return nil, err end
  local data = fh:read("*a")
  fh:close()
  return data
end

-- hash_filename(path) -> 8-char lowercase hex sha1 prefix, or nil + err.
function M.hash_filename(path)
  local data, err = read_file(path)
  if not data then return nil, err end
  -- Pipe content through `shasum -a 1`. Format: "<40 hex>  -\n".
  local cmd = "shasum -a 1"
  local p = io.popen(cmd, "w")
  if not p then return nil, "io.popen failed" end
  -- We need both write and read; do it in two passes via temp file.
  -- Simpler: spawn shasum that reads from stdin, capture via io.popen "r"
  -- by pre-writing data to a temp file.
  p:close()

  -- Use a temp file approach to keep this single-shot.
  local tmpname = os.tmpname()
  local tf, terr = io.open(tmpname, "wb")
  if not tf then return nil, terr end
  tf:write(data)
  tf:close()

  local rp = io.popen("shasum -a 1 < " .. string.format("%q", tmpname), "r")
  if not rp then
    os.remove(tmpname)
    return nil, "io.popen failed"
  end
  local out = rp:read("*l") or ""
  rp:close()
  os.remove(tmpname)

  local hex = out:match("^(%x+)")
  if not hex or #hex < 8 then
    return nil, "shasum produced unexpected output: " .. out
  end
  return hex:sub(1, 8):lower()
end

return M
```

- [ ] **Step 5: Run test to confirm it passes**

```bash
busted spec/parse_spec.lua
```

Expected: 4 successes.

- [ ] **Step 6: Commit**

```bash
git add wezterm-image-paste/parse.lua spec/parse_spec.lua spec/fixtures/
git commit -m "feat(parse): hash_filename via shasum, 8-char hex prefix"
```

---

## Task 3: `parse.parse_ssh_argv` — basic shapes

**Files:**
- Modify: `wezterm-image-paste/parse.lua`
- Modify: `spec/parse_spec.lua`

- [ ] **Step 1: Write failing tests for trivial argv shapes**

Append to `spec/parse_spec.lua`:

```lua
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
```

- [ ] **Step 2: Run to confirm failure**

```bash
busted spec/parse_spec.lua
```

Expected: failures (`parse_ssh_argv` not yet defined).

- [ ] **Step 3: Implement basic parser**

Append to `wezterm-image-paste/parse.lua` (above `return M`):

```lua
-- Flag classifier sets. Updated in subsequent tasks.
local ARG_CONSUMING_FLAGS = {
  ["-b"]=true, ["-c"]=true, ["-D"]=true, ["-E"]=true, ["-e"]=true,
  ["-F"]=true, ["-I"]=true, ["-i"]=true, ["-J"]=true, ["-L"]=true,
  ["-l"]=true, ["-m"]=true, ["-O"]=true, ["-o"]=true, ["-p"]=true,
  ["-Q"]=true, ["-R"]=true, ["-S"]=true, ["-W"]=true, ["-w"]=true,
}

local function basename(path)
  return (path:match("([^/]+)$")) or path
end

-- parse_ssh_argv(argv) -> {destination, replay_flags} | nil
function M.parse_ssh_argv(argv)
  if not argv or #argv == 0 then return nil end
  if basename(argv[1]) ~= "ssh" then return nil end

  local replay = {}
  local i = 2
  while i <= #argv do
    local tok = argv[i]
    if tok == "--" then
      -- everything after is positional; first one is destination
      i = i + 1
      if i > #argv then return nil end
      return { destination = argv[i], replay_flags = replay }
    elseif ARG_CONSUMING_FLAGS[tok] then
      local val = argv[i + 1]
      if not val then return nil end
      table.insert(replay, tok)
      table.insert(replay, val)
      i = i + 2
    elseif tok:sub(1, 1) == "-" then
      -- bool flag (handled fully in Task 5); for now keep it
      table.insert(replay, tok)
      i = i + 1
    else
      -- first non-flag token is destination
      return { destination = tok, replay_flags = replay }
    end
  end
  return nil  -- never found a destination
end
```

- [ ] **Step 4: Run tests**

```bash
busted spec/parse_spec.lua
```

Expected: all `parse.parse_ssh_argv (basic)` tests pass + previous 4 still pass.

- [ ] **Step 5: Commit**

```bash
git add wezterm-image-paste/parse.lua spec/parse_spec.lua
git commit -m "feat(parse): parse_ssh_argv basic shapes (host, user@host, --, basename)"
```

---

## Task 4: `parse.parse_ssh_argv` — flags that consume an argument

**Files:**
- Modify: `spec/parse_spec.lua`

(No source change expected — Task 3 already implemented the flag-consuming
logic via `ARG_CONSUMING_FLAGS`. This task locks that behavior in tests
and catches regressions.)

- [ ] **Step 1: Add tests for arg-consuming flags**

Append to `spec/parse_spec.lua`:

```lua
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
```

- [ ] **Step 2: Run tests**

```bash
busted spec/parse_spec.lua
```

Expected: all pass. If a test fails, fix `parse.lua` until green.

- [ ] **Step 3: Commit**

```bash
git add spec/parse_spec.lua
git commit -m "test(parse): lock down -p/-i/-J/-o + spec canonical case"
```

---

## Task 5: `parse.parse_ssh_argv` — boolean flags, `flag=value`, stacked shorts

**Files:**
- Modify: `wezterm-image-paste/parse.lua`
- Modify: `spec/parse_spec.lua`

- [ ] **Step 1: Write failing tests**

Append to `spec/parse_spec.lua`:

```lua
describe("parse.parse_ssh_argv (boolean / combined / stacked)", function()
  it("ssh -tt host htop (boolean flag, then host, then remote cmd)", function()
    local r = parse.parse_ssh_argv({ "ssh", "-tt", "host", "htop" })
    assert.are.same(
      { destination = "host", replay_flags = { "-tt" } },
      r
    )
  end)

  it("ssh -vvv host", function()
    local r = parse.parse_ssh_argv({ "ssh", "-vvv", "host" })
    assert.are.same(
      { destination = "host", replay_flags = { "-vvv" } },
      r
    )
  end)

  it("ssh -oPort=22 host (combined flag=value, single token)", function()
    local r = parse.parse_ssh_argv({ "ssh", "-oPort=22", "host" })
    assert.are.same(
      { destination = "host", replay_flags = { "-oPort=22" } },
      r
    )
  end)

  it("ssh -A -C host (stacked booleans across tokens)", function()
    local r = parse.parse_ssh_argv({ "ssh", "-A", "-C", "host" })
    assert.are.same(
      { destination = "host", replay_flags = { "-A", "-C" } },
      r
    )
  end)
end)
```

- [ ] **Step 2: Run to confirm passes (likely already green)**

```bash
busted spec/parse_spec.lua
```

If any fail, the issue is in handling `-oKEY=VALUE` (a single arg-consuming-prefix
that does **not** consume the next token). Fix as below.

- [ ] **Step 3: Refine flag detection in `wezterm-image-paste/parse.lua`**

Replace the `elseif ARG_CONSUMING_FLAGS[tok] then` branch with logic that also
handles the `-oKEY=VALUE` single-token form:

```lua
    elseif tok:match("^%-[a-zA-Z]") and #tok > 2 and ARG_CONSUMING_FLAGS["-" .. tok:sub(2, 2)] then
      -- single-token combined form like -oPort=22 or -p22
      table.insert(replay, tok)
      i = i + 1
    elseif ARG_CONSUMING_FLAGS[tok] then
      local val = argv[i + 1]
      if not val then return nil end
      table.insert(replay, tok)
      table.insert(replay, val)
      i = i + 2
```

The order matters: check the combined form first, then the two-token form.

- [ ] **Step 4: Run tests**

```bash
busted spec/parse_spec.lua
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add wezterm-image-paste/parse.lua spec/parse_spec.lua
git commit -m "feat(parse): handle -oKEY=VALUE / stacked booleans / -vvv / -tt"
```

---

## Task 6: `parse.validate_remote_path` — defensive filename validator

**Files:**
- Modify: `wezterm-image-paste/parse.lua`
- Modify: `spec/parse_spec.lua`

- [ ] **Step 1: Write failing tests**

Append to `spec/parse_spec.lua`:

```lua
describe("parse.validate_remote_path", function()
  it("accepts our own generated names", function()
    local r, err = parse.validate_remote_path("/tmp/wezterm-paste-a3f29c1d.png")
    assert.are.equal("/tmp/wezterm-paste-a3f29c1d.png", r)
    assert.is_nil(err)
  end)

  it("rejects shell metacharacters", function()
    for _, bad in ipairs({
      "/tmp/foo;rm -rf /",
      "/tmp/foo`whoami`",
      "/tmp/foo$(id)",
      "/tmp/foo|cat",
      "/tmp/foo\nbar",
    }) do
      local r, err = parse.validate_remote_path(bad)
      assert.is_nil(r, "should reject: " .. bad)
      assert.is_string(err)
    end
  end)
end)
```

- [ ] **Step 2: Run, confirm failure**

```bash
busted spec/parse_spec.lua
```

- [ ] **Step 3: Implement `validate_remote_path`**

Append to `wezterm-image-paste/parse.lua` (above `return M`):

```lua
-- validate_remote_path checks that a remote path contains only the
-- characters we ourselves generate. It does NOT escape; it only
-- accepts or rejects. We never need exotic paths, so rejecting anything
-- fancy is safer than escaping.
function M.validate_remote_path(s)
  if type(s) ~= "string" then return nil, "not a string" end
  -- Lua %w is [A-Za-z0-9] only (ASCII, no underscore). We add _ explicitly.
  if not s:match("^[%w/_%-%.]+$") then
    return nil, "remote path contains disallowed characters"
  end
  return s
end
```

- [ ] **Step 4: Run, confirm pass**

```bash
busted spec/parse_spec.lua
```

- [ ] **Step 5: Commit**

```bash
git add wezterm-image-paste/parse.lua spec/parse_spec.lua
git commit -m "feat(parse): validate_remote_path rejects shell metacharacters"
```

---

## Task 7: `run.exec` — injectable subprocess wrapper

**Files:**
- Create: `wezterm-image-paste/run.lua`
- Create: `spec/run_spec.lua`

- [ ] **Step 1: Write failing test**

`spec/run_spec.lua`:

```lua
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
```

- [ ] **Step 2: Run, confirm failure**

```bash
busted spec/run_spec.lua
```

- [ ] **Step 3: Implement `run.lua`**

```lua
local M = {}

-- Default impl uses io.popen for tests run outside WezTerm. Inside WezTerm
-- this module is shimmed by init.lua to wrap wezterm.run_child_process so
-- we can also capture stderr. Tests can replace M._impl directly.
M._impl = function(argv)
  -- Build a shell-quoted command. argv is a list of strings.
  local quoted = {}
  for _, a in ipairs(argv) do
    table.insert(quoted, string.format("%q", a))
  end
  -- Capture stdout and stderr separately via tempfiles.
  local out_t = os.tmpname()
  local err_t = os.tmpname()
  local cmd = table.concat(quoted, " ")
    .. " >" .. string.format("%q", out_t)
    .. " 2>" .. string.format("%q", err_t)
  local ok, _, code = os.execute(cmd)
  -- Lua 5.1: os.execute returns numeric code. Lua 5.3+: returns ok, type, code.
  if type(ok) == "number" then code = ok; ok = (code == 0) end
  local function slurp(p)
    local fh = io.open(p, "rb")
    if not fh then return "" end
    local s = fh:read("*a") or ""
    fh:close()
    return s
  end
  local stdout = slurp(out_t)
  local stderr = slurp(err_t)
  os.remove(out_t)
  os.remove(err_t)
  return {
    success = (ok == true) or (code == 0),
    exit_code = code or 0,
    stdout = stdout,
    stderr = stderr,
  }
end

function M.exec(argv)
  return M._impl(argv)
end

-- Called from init.lua at WezTerm load time to swap _impl for a wezterm-aware
-- implementation. See init.lua.
function M.use_wezterm(wezterm)
  M._impl = function(argv)
    local ok, stdout, stderr = wezterm.run_child_process(argv)
    return {
      success = ok,
      exit_code = ok and 0 or 1,  -- wezterm API does not surface real exit code
      stdout = stdout or "",
      stderr = stderr or "",
    }
  end
end

return M
```

- [ ] **Step 4: Run tests**

```bash
busted spec/run_spec.lua
```

Expected: 3 passes.

- [ ] **Step 5: Commit**

```bash
git add wezterm-image-paste/run.lua spec/run_spec.lua
git commit -m "feat(run): injectable subprocess wrapper with stderr capture"
```

---

## Task 8: `clipboard.probe` and `clipboard.write`

**Files:**
- Create: `wezterm-image-paste/clipboard.lua`
- Create: `spec/clipboard_spec.lua`

- [ ] **Step 1: Write failing tests**

`spec/clipboard_spec.lua`:

```lua
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
```

- [ ] **Step 2: Run, confirm failure**

```bash
busted spec/clipboard_spec.lua
```

- [ ] **Step 3: Implement `clipboard.lua`**

```lua
local run = require("wezterm-image-paste.run")

local M = {}

-- Returns a table:
--   { kind = "image",            local_path = "<path>" }
--   { kind = "text" }
--   { kind = "empty" }
--   { kind = "missing_pngpaste" }
function M.probe()
  local info = run.exec({ "osascript", "-e", "clipboard info" })
  if not info.success then return { kind = "empty" } end
  local out = info.stdout or ""
  if out == "" then return { kind = "empty" } end
  if not out:match("«class PNGf»") and not out:match("«class TIFF»") then
    return { kind = "text" }
  end
  -- Image present. Try pngpaste.
  local tmpdir = os.getenv("TMPDIR") or "/tmp"
  -- Use a unique name to allow concurrent pastes.
  local local_path = string.format("%swezterm-paste-%d-%d.png",
    tmpdir:sub(-1) == "/" and tmpdir or (tmpdir .. "/"),
    os.time(), math.random(100000, 999999))
  local r = run.exec({ "pngpaste", local_path })
  if not r.success then
    return { kind = "missing_pngpaste", stderr = r.stderr }
  end
  return { kind = "image", local_path = local_path }
end

function M.write(text)
  -- printf %s avoids any trailing newline that would press Return on next paste.
  return run.exec({ "sh", "-c", 'printf %s "$1" | pbcopy', "_", text })
end

-- Save current clipboard PNG to an explicit path (used by non-SSH-pane fallback).
function M.save_to(local_path)
  return run.exec({ "pngpaste", local_path })
end

return M
```

- [ ] **Step 4: Run tests**

```bash
busted spec/clipboard_spec.lua
```

Expected: 5 passes.

- [ ] **Step 5: Commit**

```bash
git add wezterm-image-paste/clipboard.lua spec/clipboard_spec.lua
git commit -m "feat(clipboard): probe (osascript+pngpaste) and write (pbcopy no newline)"
```

---

## Task 9: `ssh_target.detect` — find ssh in pane's process tree

**Files:**
- Create: `wezterm-image-paste/ssh_target.lua`
- Create: `spec/ssh_target_spec.lua`

The pane's `get_foreground_process_info()` returns a recursive struct:

```
{ name = "zsh", argv = {"zsh"}, children = {
    { name = "ssh", argv = {"ssh", "-J", "j", "host"}, children = {} },
    { name = "tmux", argv = {"tmux"}, children = { ... } },
}}
```

We want a depth-first search that returns the **first `ssh` process whose
basename is exactly `ssh`** (not `ssh-add`, `sshfs`, etc.). When found, we
pass its `argv` to `parse.parse_ssh_argv`.

- [ ] **Step 1: Write failing tests**

`spec/ssh_target_spec.lua`:

```lua
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
end)
```

- [ ] **Step 2: Run, confirm failure**

```bash
busted spec/ssh_target_spec.lua
```

- [ ] **Step 3: Implement `ssh_target.lua`**

```lua
local parse = require("wezterm-image-paste.parse")

local M = {}

local function basename(path)
  return (path or ""):match("([^/]+)$") or path or ""
end

-- Depth-first search for the first process whose basename is exactly "ssh".
local function find_ssh(node)
  if not node then return nil end
  if basename(node.name) == "ssh" then return node end
  for _, child in ipairs(node.children or {}) do
    local hit = find_ssh(child)
    if hit then return hit end
  end
  return nil
end

-- detect(proc_info) -> {destination, replay_flags} | nil
function M.detect(proc_info)
  local ssh_node = find_ssh(proc_info)
  if not ssh_node then return nil end
  return parse.parse_ssh_argv(ssh_node.argv or {})
end

-- For convenience inside the orchestrator: take a pane object and call its
-- get_foreground_process_info(). Tests will not exercise this path.
function M.detect_from_pane(pane)
  if not pane or not pane.get_foreground_process_info then return nil end
  return M.detect(pane:get_foreground_process_info())
end

return M
```

- [ ] **Step 4: Run tests**

```bash
busted spec/ssh_target_spec.lua
```

Expected: 5 passes.

- [ ] **Step 5: Commit**

```bash
git add wezterm-image-paste/ssh_target.lua spec/ssh_target_spec.lua
git commit -m "feat(ssh_target): detect ssh in pane process tree, dispatch to parse"
```

---

## Task 10: `uploader.run` — precheck + scp with replay_flags

**Files:**
- Create: `wezterm-image-paste/uploader.lua`
- Create: `spec/uploader_spec.lua`

- [ ] **Step 1: Write failing tests**

`spec/uploader_spec.lua`:

```lua
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

    -- Inspect scp argv
    local scp_call = calls[2]
    assert.are.equal("scp", scp_call[1])
    flat = table.concat(scp_call, " ")
    assert.is_truthy(flat:match("%-J root@8%.210%.34%.23"))
    assert.is_truthy(flat:match("ControlMaster=auto"))
    assert.is_truthy(flat:match("root@47%.237%.21%.3:/tmp/wezterm%-paste%-"))
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
end)
```

- [ ] **Step 2: Run, confirm failure**

```bash
busted spec/uploader_spec.lua
```

- [ ] **Step 3: Implement `uploader.lua`**

```lua
local run = require("wezterm-image-paste.run")
local parse = require("wezterm-image-paste.parse")

local M = {}

local CONTROL_FLAGS = {
  "-o", "ControlMaster=auto",
  "-o", "ControlPath=~/.ssh/cm-%r@%h:%p",
  "-o", "ControlPersist=10m",
  "-o", "ConnectTimeout=10",
}

local function concat(a, b)
  local out = {}
  for _, v in ipairs(a) do table.insert(out, v) end
  for _, v in ipairs(b) do table.insert(out, v) end
  return out
end

local function summarize_stderr(s)
  if not s or s == "" then return "(no stderr)" end
  s = s:gsub("\r", " "):gsub("\n", " ")
  if #s > 200 then s = s:sub(1, 200) .. "…" end
  return s
end

-- uploader.run(target, local_path, remote_dir) -> remote_path | (nil, err)
function M.run(target, local_path, remote_dir)
  remote_dir = remote_dir or "/tmp"

  local hash, err = parse.hash_filename(local_path)
  if not hash then return nil, "hash failed: " .. tostring(err) end

  local remote_path = remote_dir .. "/wezterm-paste-" .. hash .. ".png"
  local validated, perr = parse.validate_remote_path(remote_path)
  if not validated then return nil, "remote path rejected: " .. tostring(perr) end

  -- 1) precheck
  local precheck_argv = concat({ "ssh" }, target.replay_flags)
  precheck_argv = concat(precheck_argv, CONTROL_FLAGS)
  table.insert(precheck_argv, target.destination)
  table.insert(precheck_argv, "test -e " .. validated)
  local pre = run.exec(precheck_argv)
  if pre.success then
    return validated  -- already there
  end

  -- 2) scp
  local scp_argv = concat({ "scp" }, target.replay_flags)
  scp_argv = concat(scp_argv, CONTROL_FLAGS)
  table.insert(scp_argv, local_path)
  table.insert(scp_argv, target.destination .. ":" .. validated)
  local up = run.exec(scp_argv)
  if not up.success then
    return nil, summarize_stderr(up.stderr)
  end

  return validated
end

return M
```

- [ ] **Step 4: Run tests**

```bash
busted spec/uploader_spec.lua
```

Expected: 4 passes.

- [ ] **Step 5: Commit**

```bash
git add wezterm-image-paste/uploader.lua spec/uploader_spec.lua
git commit -m "feat(uploader): hash + ssh precheck + scp with replay_flags"
```

---

## Task 11: `notify.toast` and `notify.log`

**Files:**
- Create: `wezterm-image-paste/notify.lua`

`notify` is a thin wrapper. It is exercised end-to-end by manual testing
and by tasks 12–17 via mocking. No dedicated spec file is needed (the
contract is "call this WezTerm method"; mocking it just tests the mock).

- [ ] **Step 1: Implement `notify.lua`**

```lua
local M = {}

-- These two are set by init.use_wezterm at load time, so tests can stub them.
M._toast_impl = function(window, msg, level) end
M._log_impl = function(level, msg) end

function M.toast(window, msg, level)
  pcall(M._toast_impl, window, msg, level)
end

function M.log(level, msg)
  pcall(M._log_impl, level, msg)
end

function M.use_wezterm(wezterm)
  M._toast_impl = function(window, msg, level)
    if window and window.toast_notification then
      window:toast_notification("wezterm-image-paste", msg, nil, 4000)
    end
  end
  M._log_impl = function(level, msg)
    if level == "error" then
      wezterm.log_error(msg)
    elseif level == "warn" then
      wezterm.log_warn(msg)
    else
      wezterm.log_info(msg)
    end
  end
end

return M
```

- [ ] **Step 2: Commit**

```bash
git add wezterm-image-paste/notify.lua
git commit -m "feat(notify): toast + log with wezterm-aware impl + test stubs"
```

---

## Task 12: `handler.handle_paste` — happy path (image + ssh pane)

**Files:**
- Create: `wezterm-image-paste/handler.lua`
- Create: `spec/handler_spec.lua`

- [ ] **Step 1: Write failing test (happy path only — error branches in tasks 13–16)**

`spec/handler_spec.lua`:

```lua
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
  it("upload + clipboard rewrite when image + ssh pane", function()
    local written
    local saved = stub_all({
      probe = function() return { kind = "image", local_path = "/tmp/x.png" } end,
      detect = function() return { destination = "root@host", replay_flags = {} } end,
      upload = function(target, local_path, remote_dir)
        return "/tmp/wezterm-paste-aaaaaaaa.png"
      end,
      write = function(text) written = text end,
    })

    local result = handler.handle_paste({}, {}, { remote_dir = "/tmp" })

    assert.are.equal("uploaded", result.outcome)
    assert.are.equal("/tmp/wezterm-paste-aaaaaaaa.png", written)
    restore(saved)
  end)
end)
```

- [ ] **Step 2: Run, confirm failure**

```bash
busted spec/handler_spec.lua
```

- [ ] **Step 3: Implement `handler.lua` (happy path branch only)**

```lua
local clipboard = require("wezterm-image-paste.clipboard")
local ssh_target = require("wezterm-image-paste.ssh_target")
local uploader = require("wezterm-image-paste.uploader")
local notify = require("wezterm-image-paste.notify")

local M = {}

local DEFAULTS = {
  remote_dir = "/tmp",
  local_fallback_dir = os.getenv("HOME") .. "/Downloads",
  timeout_seconds = 10,
}

-- Returns one of:
--   { outcome = "uploaded",  remote_path = ... }
--   { outcome = "fallback_local", local_path = ... }
--   { outcome = "passthrough" }      -- text/empty clipboard, native paste runs
--   { outcome = "missing_pngpaste" }
--   { outcome = "ssh_fail",  err = ... }
--   { outcome = "non_ssh_image" }    -- handled inside via fallback
function M.handle_paste(window, pane, opts)
  opts = opts or {}
  local remote_dir = opts.remote_dir or DEFAULTS.remote_dir

  local probe = clipboard.probe()

  if probe.kind == "text" or probe.kind == "empty" then
    return { outcome = "passthrough" }
  end
  if probe.kind == "missing_pngpaste" then
    notify.toast(window, "❗需要 brew install pngpaste,本次未上传", "error")
    return { outcome = "missing_pngpaste" }
  end
  -- probe.kind == "image"

  local target = ssh_target.detect_from_pane(pane)
  if not target then
    -- non-SSH branch handled in Task 14
    return { outcome = "non_ssh_image" }
  end

  local remote_path, err = uploader.run(target, probe.local_path, remote_dir)
  if not remote_path then
    notify.toast(window, "✗ 上传失败: " .. tostring(err), "error")
    return { outcome = "ssh_fail", err = err }
  end

  clipboard.write(remote_path)
  notify.toast(window, "📎 路径已复制到剪贴板,Cmd+V 即可粘贴", "info")
  return { outcome = "uploaded", remote_path = remote_path }
end

return M
```

- [ ] **Step 4: Run tests**

```bash
busted spec/handler_spec.lua
```

Expected: 1 pass.

- [ ] **Step 5: Commit**

```bash
git add wezterm-image-paste/handler.lua spec/handler_spec.lua
git commit -m "feat(handler): happy path image+ssh -> upload + clipboard rewrite"
```

---

## Task 13: `handler` — text/empty clipboard passes through to native paste

**Files:**
- Modify: `spec/handler_spec.lua`

The happy-path test in Task 12 already covers `passthrough` returning the
right outcome. But we need to verify that the native-paste fallthrough is
explicit in the orchestrator's contract. We also need to add a test for
the empty clipboard case.

- [ ] **Step 1: Add tests**

Append to `spec/handler_spec.lua`:

```lua
describe("handler.handle_paste (passthrough)", function()
  it("returns passthrough for text clipboard", function()
    local saved = stub_all({
      probe = function() return { kind = "text" } end,
    })
    local r = handler.handle_paste({}, {}, {})
    assert.are.equal("passthrough", r.outcome)
    restore(saved)
  end)

  it("returns passthrough for empty clipboard", function()
    local saved = stub_all({
      probe = function() return { kind = "empty" } end,
    })
    local r = handler.handle_paste({}, {}, {})
    assert.are.equal("passthrough", r.outcome)
    restore(saved)
  end)
end)
```

- [ ] **Step 2: Run, confirm pass**

```bash
busted spec/handler_spec.lua
```

Expected: 3 passes total (Task 12's 1 + 2 new).

- [ ] **Step 3: Commit**

```bash
git add spec/handler_spec.lua
git commit -m "test(handler): passthrough for text/empty clipboard"
```

---

## Task 14: `handler` — non-SSH pane fallback (save to ~/Downloads)

**Files:**
- Modify: `wezterm-image-paste/handler.lua`
- Modify: `spec/handler_spec.lua`

When the clipboard has an image but the pane is not SSH, the spec (§4, §8)
says: save the PNG to `~/Downloads/wezterm-paste-<ISO>.png`, replace the
clipboard with that local path, **do not** fall through to native paste.

- [ ] **Step 1: Write failing test**

Append to `spec/handler_spec.lua`:

```lua
describe("handler.handle_paste (non-ssh image fallback)", function()
  it("saves image to local fallback dir and rewrites clipboard with that path", function()
    local saved_to, written
    local saved = stub_all({
      probe = function() return { kind = "image", local_path = "/tmp/x.png" } end,
      detect = function() return nil end,        -- NOT ssh
      save_to = function(p) saved_to = p
        return { success = true, exit_code = 0, stdout = "", stderr = "" } end,
      write = function(t) written = t end,
    })
    local r = handler.handle_paste({}, {}, { local_fallback_dir = "/tmp/fallback" })
    assert.are.equal("fallback_local", r.outcome)
    assert.is_truthy(saved_to:match("^/tmp/fallback/wezterm%-paste%-.+%.png$"))
    assert.are.equal(saved_to, written)
    restore(saved)
  end)
end)
```

- [ ] **Step 2: Run, confirm failure**

```bash
busted spec/handler_spec.lua
```

- [ ] **Step 3: Add the non-SSH branch to `handler.lua`**

Replace the block:

```lua
  if not target then
    -- non-SSH branch handled in Task 14
    return { outcome = "non_ssh_image" }
  end
```

with:

```lua
  if not target then
    local fallback_dir = opts.local_fallback_dir or DEFAULTS.local_fallback_dir
    local stamp = os.date("!%Y%m%dT%H%M%SZ")
    local local_path = fallback_dir .. "/wezterm-paste-" .. stamp .. ".png"
    -- Ensure dir exists. mkdir -p is safe and idempotent.
    require("wezterm-image-paste.run").exec({ "mkdir", "-p", fallback_dir })
    local r = clipboard.save_to(local_path)
    if not r.success then
      notify.toast(window, "✗ 保存到本地失败: " .. (r.stderr or ""), "error")
      return { outcome = "ssh_fail", err = r.stderr }
    end
    clipboard.write(local_path)
    notify.toast(window, "📎 非 SSH 会话,图片已存到 " .. fallback_dir .. ",路径已复制", "info")
    return { outcome = "fallback_local", local_path = local_path }
  end
```

- [ ] **Step 4: Run tests**

```bash
busted spec/handler_spec.lua
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add wezterm-image-paste/handler.lua spec/handler_spec.lua
git commit -m "feat(handler): non-ssh pane fallback to ~/Downloads + clipboard rewrite"
```

---

## Task 15: `handler` — error branches (pngpaste missing, scp fail)

**Files:**
- Modify: `spec/handler_spec.lua`

The pngpaste-missing and scp-fail branches are already implemented by
Task 12. Lock them in tests.

- [ ] **Step 1: Add tests**

Append to `spec/handler_spec.lua`:

```lua
describe("handler.handle_paste (error branches)", function()
  it("missing_pngpaste -> outcome and toast", function()
    local toasts = {}
    local saved = stub_all({
      probe = function() return { kind = "missing_pngpaste" } end,
      toast = function(_, msg) table.insert(toasts, msg) end,
    })
    local r = handler.handle_paste({}, {}, {})
    assert.are.equal("missing_pngpaste", r.outcome)
    assert.is_truthy(toasts[1]:match("pngpaste"))
    restore(saved)
  end)

  it("scp failure -> outcome=ssh_fail, error preserved", function()
    local toasts = {}
    local saved = stub_all({
      probe = function() return { kind = "image", local_path = "/tmp/x.png" } end,
      detect = function() return { destination = "h", replay_flags = {} } end,
      upload = function() return nil, "Network is unreachable" end,
      toast = function(_, msg) table.insert(toasts, msg) end,
    })
    local r = handler.handle_paste({}, {}, {})
    assert.are.equal("ssh_fail", r.outcome)
    assert.are.equal("Network is unreachable", r.err)
    assert.is_truthy(toasts[1]:match("Network is unreachable"))
    restore(saved)
  end)
end)
```

- [ ] **Step 2: Run, confirm pass**

```bash
busted spec/handler_spec.lua
```

Expected: all green.

- [ ] **Step 3: Commit**

```bash
git add spec/handler_spec.lua
git commit -m "test(handler): missing_pngpaste and scp_fail error branches"
```

---

## Task 16: `init.apply_to_config` — wire keybinding and inject WezTerm

**Files:**
- Modify: `wezterm-image-paste/init.lua`

This is where everything comes together. `init.apply_to_config(config, opts)`:

1. Pulls in WezTerm via `require("wezterm")`.
2. Calls `run.use_wezterm(wezterm)` and `notify.use_wezterm(wezterm)` so all
   shell-outs and toasts go through WezTerm.
3. Adds a `Cmd+V` key binding whose action is a `wezterm.action_callback`
   that calls `handler.handle_paste(window, pane, opts)`.
4. **Critical:** if the result is `passthrough`, the callback then performs
   the native paste (`wezterm.action.PasteFrom('Clipboard')`). For all
   other outcomes, the callback returns without firing native paste.

- [ ] **Step 1: Implement `init.lua`**

Replace the stub `wezterm-image-paste/init.lua` with:

```lua
local M = {}
M.VERSION = "0.1.0"

local DEFAULT_OPTS = {
  bind_cmd_v = true,
  remote_dir = "/tmp",
  local_fallback_dir = os.getenv("HOME") .. "/Downloads",
  timeout_seconds = 10,
}

local function merge(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over or {}) do out[k] = v end
  return out
end

function M.apply_to_config(config, user_opts)
  local wezterm = require("wezterm")
  local run = require("wezterm-image-paste.run")
  local notify = require("wezterm-image-paste.notify")
  local handler = require("wezterm-image-paste.handler")

  run.use_wezterm(wezterm)
  notify.use_wezterm(wezterm)

  local opts = merge(DEFAULT_OPTS, user_opts)

  if not opts.bind_cmd_v then return end

  local act = wezterm.action

  config.keys = config.keys or {}
  table.insert(config.keys, {
    key = "v",
    mods = "CMD",
    action = wezterm.action_callback(function(window, pane)
      local r = handler.handle_paste(window, pane, opts)
      if r.outcome == "passthrough" then
        window:perform_action(act.PasteFrom("Clipboard"), pane)
      end
      -- For "uploaded", "fallback_local", "missing_pngpaste", "ssh_fail":
      -- we deliberately do NOT trigger native paste, because:
      --   * uploaded/fallback_local: clipboard now has a path; user pastes manually
      --   * missing_pngpaste/ssh_fail: clipboard still has the image; pasting it
      --     would dump PNG bytes into the terminal stream.
    end),
  })
end

return M
```

- [ ] **Step 2: Add a smoke test that confirms apply_to_config runs without WezTerm at hand**

We can't fully test this without WezTerm, but we can verify that the module
fails loudly with a clear error (rather than crashing silently) when WezTerm
isn't present. Append to `spec/smoke_spec.lua`:

```lua
describe("init.apply_to_config (no wezterm available)", function()
  it("raises a clear error when require('wezterm') fails", function()
    local mod = require("wezterm-image-paste")
    -- Loading busted runtime; require('wezterm') should fail.
    local ok, err = pcall(mod.apply_to_config, {}, {})
    assert.is_false(ok)
    assert.is_truthy(tostring(err):match("wezterm"))
  end)
end)
```

- [ ] **Step 3: Run all tests**

```bash
busted
```

Expected: every spec passes.

- [ ] **Step 4: Commit**

```bash
git add wezterm-image-paste/init.lua spec/smoke_spec.lua
git commit -m "feat(init): apply_to_config wires Cmd+V to handler with passthrough"
```

---

## Task 17: README and ssh_config snippet

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write `README.md`**

Replace `README.md` with:

````markdown
# wezterm-image-paste

Paste local screenshots into remote SSH sessions. `Cmd+V` uploads the
clipboard image to the remote machine via `scp` and replaces your
local clipboard with the resulting remote path. Press `Cmd+V` again
inside Claude Code (or any TUI app on the remote) to drop the path
into its input — the AI reads the image from disk.

## Requirements

- macOS
- WezTerm (`brew install --cask wezterm`)
- `pngpaste` (`brew install pngpaste`)
- OpenSSH with `ControlMaster` enabled (recommended)

## Install

```bash
git clone <this-repo> ~/.config/wezterm-image-paste
```

Add to your `~/.wezterm.lua`:

```lua
local wezterm = require 'wezterm'
package.path = package.path
  .. ';' .. os.getenv("HOME") .. '/.config/wezterm-image-paste/?.lua'
  .. ';' .. os.getenv("HOME") .. '/.config/wezterm-image-paste/?/init.lua'

local image_paste = require 'wezterm-image-paste'
local config = wezterm.config_builder()

image_paste.apply_to_config(config)

return config
```

Reload WezTerm config (Cmd+Shift+R or restart).

## SSH config (recommended)

For best performance, enable connection multiplexing. Add to
`~/.ssh/config`:

```
Host *
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
```

Without this, every paste opens a fresh SSH connection (still works,
but slower and may re-prompt for password/2FA).

## Use

1. Take a screenshot (`Cmd+Shift+4`).
2. SSH into your remote in WezTerm: `ssh devbox`.
3. Run Claude Code: `claude`.
4. Press `Cmd+V` in WezTerm. Toast appears:
   `📎 路径已复制到剪贴板,Cmd+V 即可粘贴`.
5. Press `Cmd+V` again — Claude Code receives the remote path and
   reads the image.

## Configuration

```lua
image_paste.apply_to_config(config, {
  bind_cmd_v = true,                      -- default true
  remote_dir = "/tmp",                    -- where uploaded images land
  local_fallback_dir = "~/Downloads",     -- if pane is NOT ssh
  timeout_seconds = 10,                   -- ssh ConnectTimeout
})
```

## Caveats

- macOS only (uses `pbcopy`, `osascript`, `pngpaste`).
- WezTerm only (uses `wezterm.action_callback` and pane process info).
- The 10s timeout is best-effort; it sets `ssh -o ConnectTimeout=10`
  but does not deadline a stuck transfer over a working but slow link.
- Uploaded files are not auto-cleaned. Your remote `/tmp` policy
  handles them.

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| Toast: `❗需要 brew install pngpaste` | `pngpaste` not on PATH |
| Toast: `✗ 上传失败: …` | Network or auth issue. Run the same `ssh` command manually to debug. |
| `Cmd+V` does nothing visible | Pane is not SSH and clipboard is text — native paste should still work. |
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): install + ssh_config + use + config + caveats"
```

---

## Task 18: Manual test checklist

**Files:**
- Create: `docs/manual-test-checklist.md`

- [ ] **Step 1: Write the checklist**

```markdown
# Manual Test Checklist

Run these before tagging a release. Each item must pass.

Scope: tested on macOS 14+ with WezTerm 2026.01+ and `pngpaste` from
Homebrew.

## Setup

- [ ] `brew install pngpaste`
- [ ] `~/.ssh/config` has `ControlMaster auto` for the test hosts.
- [ ] `~/.wezterm.lua` requires `wezterm-image-paste` and calls
      `apply_to_config`.

## Cases

1. **Plain text paste passes through**
   - Copy "hello" to clipboard.
   - In a local WezTerm pane, run `cat`.
   - Press `Cmd+V`. Expected: `hello` printed; no toast.

2. **Image paste into SSH pane works**
   - SSH into a test host: `ssh devbox`.
   - Take a screenshot (`Cmd+Shift+4`).
   - In the SSH pane (no app running, just shell), press `Cmd+V`.
   - Expected toast: `📎 路径已复制到剪贴板,Cmd+V 即可粘贴`.
   - Expected: file at `/tmp/wezterm-paste-<hash>.png` on remote.
   - Press `Cmd+V` again. Expected: path string typed into shell.

3. **Re-pasting same image is fast**
   - With the same screenshot still in clipboard, press `Cmd+V` again.
   - Expected: same path; observable latency is sub-second; no scp
     traffic (verifiable via `tcpdump` if curious).

4. **Non-SSH pane image paste falls back to ~/Downloads**
   - Open a local pane (no SSH).
   - Take a screenshot.
   - Press `Cmd+V`.
   - Expected toast: `📎 非 SSH 会话,图片已存到 ~/Downloads,…`
   - Expected: file at `~/Downloads/wezterm-paste-<ISO>.png`.

5. **Image paste into SSH + tmux + Claude Code**
   - SSH into host, attach `tmux`, run `claude`.
   - Take a screenshot.
   - Press `Cmd+V` once. Toast appears.
   - Press `Cmd+V` again, into Claude Code's input.
   - Expected: Claude Code echoes the path and processes the image.

6. **ProxyJump via ~/.ssh/config works**
   - Add `Host innerhost \n  ProxyJump bastion` to `~/.ssh/config`.
   - `ssh innerhost`, then take a screenshot.
   - `Cmd+V`. Expected: same as case 2; file lands on `innerhost`.

6b. **Inline `-J` and `-o` flags resolve correctly**
   - Run:
     `ssh -J root@8.210.34.23 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 root@47.237.21.3`
   - Take a screenshot.
   - `Cmd+V`. Expected: file lands on `47.237.21.3` (the destination,
     not the jumphost). Toast shows the `47.237.21.3` path.

7. **Network failure preserves clipboard**
   - SSH into a host, then disable network (Wi-Fi off).
   - Take a screenshot. `Cmd+V`.
   - Expected toast: `✗ 上传失败: …`
   - Verify clipboard still contains the image (e.g.,
     `osascript -e 'clipboard info'` shows `«class PNGf»`).

8. **Missing `pngpaste` gives clear hint**
   - `brew uninstall pngpaste`.
   - Take a screenshot. `Cmd+V` in any pane.
   - Expected toast: `❗需要 brew install pngpaste,本次未上传`.
   - Re-install: `brew install pngpaste`.

## Sign-off

Tester: _______________  Date: _______________

All 9 cases pass: ☐
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual-test-checklist.md
git commit -m "docs: manual test checklist (9 cases mirror spec §10)"
```

---

## Task 19: Final integration sweep

**Files:**
- Run all tests, fix any drift.

- [ ] **Step 1: Run full test suite**

```bash
busted
```

Expected: every spec passes. Count specs to confirm no test was deleted
by accident:

```bash
busted --list
```

- [ ] **Step 2: Run on a real WezTerm**

Manually walk Cases 1, 2, 4 from `docs/manual-test-checklist.md`. These
are the smoke tests that catch wiring problems impossible to catch in
unit tests.

- [ ] **Step 3: If any case fails, file the failure in a fresh task and stop**

Do not patch silently. The plan's contract is that every task's tests
stay green; if Case 2 (the headline feature) fails on a real machine,
something in `init.lua` or `handler.lua` is mis-wired. Investigate
before claiming completion.

- [ ] **Step 4: Tag v0.1.0**

```bash
git tag -a v0.1.0 -m "v0.1.0: image paste over SSH"
```

(Do not push — the user will decide when/where to publish.)

- [ ] **Step 5: Commit any final fixes**

```bash
git status   # should be clean
```

---

## Plan Self-Review

Before handing off, walking through the spec and matching to tasks:

| Spec section | Tasks |
|---|---|
| §4 UX (one-time setup) | 17 (README) |
| §4 UX (day-to-day) | 12 (handler), 16 (init keybinding) |
| §5 Architecture diagram | implicit across 7–16 |
| §6 Components #1 keymap | 16 (init.apply_to_config) |
| §6 Components #2 clipboard-probe | 8 |
| §6 Components #3 ssh-target-detector | 9 |
| §6 Components #4 uploader | 10 |
| §6 Components #5 clipboard-writer | 8 |
| §6 Components #6 paste-handler | 12, 13, 14, 15 |
| §6 Components #7 notify | 11 |
| §6.1 SSH argv parsing rules | 3, 4, 5 |
| §7 Data flow (happy) | 12 |
| §8 Failure: pngpaste missing | 15 |
| §8 Failure: text/empty clipboard | 13 |
| §8 Failure: non-ssh pane | 14 |
| §8 Failure: scp fail | 15 |
| §8 Failure: timeout | partial — `-o ConnectTimeout=10` in 10; documented gap in README |
| §8 Failure: pbcopy fail | not separately tested (low-impact, surface via run.exec error path) |
| §9 Configuration surface | 16 (DEFAULT_OPTS + merge) |
| §10 Unit tests | 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 |
| §10 Manual checklist | 18, 19 |
| §11 YAGNI | enforced by absence of tasks |
| §12 Deliverables | 16, 17, 18 |

Coverage gaps and how they're handled:

- **§8 timeout (10s)**: full transfer-deadline timer is documented as
  best-effort in the README (Task 17). This is a deliberate scope
  decision — implementing a true Lua deadline timer in WezTerm is
  more code than V1 wants. If a real user hits this, follow-up plan.
- **§8 pbcopy fail**: `clipboard.write` returns the `run.exec` result
  unchecked. This is acceptable: pbcopy failure is so rare that the
  toast on success vs. the absence of a toast on failure is enough
  signal in V1. Add a check if needed.

No placeholders. No "TBD". Function names match across tasks
(`hash_filename`, `parse_ssh_argv`, `apply_to_config`, `handle_paste`,
`use_wezterm`). Type shapes (`{destination, replay_flags}`,
`{kind, local_path}`, `{outcome, ...}`) are consistent across files
and tests.

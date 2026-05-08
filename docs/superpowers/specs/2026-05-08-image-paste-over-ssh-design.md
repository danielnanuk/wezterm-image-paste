# Image Paste Over SSH — Design Spec

**Date:** 2026-05-08
**Owner:** danielnanuk@gmail.com
**Status:** Approved (pending implementation plan)
**Base project:** WezTerm (macOS, Lua-only customization, no Rust changes)

---

## 1. Problem

When the user runs Claude Code (or Aider, or any TUI AI tool) on a remote
machine via SSH, there is no way to paste a local screenshot into the AI's
input. Today the workflow is:

1. Take screenshot locally → image is in macOS clipboard.
2. Manually save the screenshot to a file locally.
3. Manually `scp` it to the remote machine.
4. Manually type the remote path into Claude Code.

We want the muscle-memory `Cmd+V` to collapse steps 2–4.

## 2. Goals

- One-keystroke (`Cmd+V`) flow that lands a remote file path on the macOS
  clipboard, ready for the user to paste into the running TUI app.
- Works with the user's existing `~/.ssh/config`, including `ProxyJump`,
  jumphosts, custom identities, port forwards, etc.
- Works with the user's normal SSH workflow (`ssh user@host` from a shell),
  not only with `wezterm ssh`.
- Works when the remote runs `tmux` and Claude Code inside it.
- Zero deployment on the remote machine. Anything we need (`scp`) is
  already part of OpenSSH.
- Local installation is one Lua file plus one Homebrew package.

## 3. Non-Goals (V1)

- Bidirectional clipboard sync (remote→local). Out of scope.
- Pasting non-image binaries (video, PDF, archives). Out of scope.
- Image compression / resize. Out of scope (current networks are fast
  enough; revisit only if a real user hits a real limit).
- In-terminal preview of the pasted image. Out of scope.
- Multi-host fan-out (paste to N hosts). Out of scope.
- Auto-cleanup of `/tmp/wezterm-paste-*.png` on the remote. The remote
  machine's normal `/tmp` policy handles it.
- Windows / Linux client support. macOS only.
- iTerm2 / Ghostty / Alacritty / Kitty adapters. WezTerm only.
- Modifying WezTerm's Rust core, or upstreaming to WezTerm. The whole
  feature lives in user Lua config.
- Synthesizing the second paste keystroke into the running app. The user
  presses `Cmd+V` again themselves; Claude Code handles it.

## 4. User-Facing UX

### One-time setup

```bash
brew install pngpaste                       # macOS clipboard PNG reader
brew install wezterm                        # if not already installed
```

Add to `~/.wezterm.lua`:

```lua
local image_paste = require 'wezterm-image-paste'
local config = wezterm.config_builder()
image_paste.apply_to_config(config)         -- registers Cmd+V handler
return config
```

Ensure the user's `~/.ssh/config` has SSH connection multiplexing enabled
(strongly recommended; without it, every paste opens a brand-new SSH
connection):

```
Host *
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
```

### Day-to-day

1. Take a screenshot (`Cmd+Shift+4`). The PNG is in the macOS clipboard.
2. SSH to the remote machine in WezTerm: `ssh devbox`.
3. Run Claude Code on the remote: `claude`.
4. Press `Cmd+V` in WezTerm.
5. WezTerm:
   - Detects the clipboard contains an image.
   - Detects the foreground process is `ssh` to host `devbox`.
   - Uploads the PNG via `scp` to `/tmp/wezterm-paste-<sha1[:8]>.png` on
     `devbox`, reusing the existing SSH ControlMaster.
   - Replaces the macOS clipboard with the text
     `/tmp/wezterm-paste-<sha1[:8]>.png` (no trailing newline).
   - Shows a toast: `📎 路径已复制到剪贴板,Cmd+V 即可粘贴`.
6. The user presses `Cmd+V` again (now into Claude Code's input field).
   Claude Code receives the path text and reads the file as it would for
   any pasted file path.

The screen does **not** auto-paste. The user controls when the path lands
in the running app, which means they can verify the toast first and aim
the cursor at the right input.

### Behavior when clipboard is not an image

The Lua handler delegates to WezTerm's native paste action. The user sees
the existing behavior. Nothing changes.

### Behavior when the foreground pane is not SSH (but clipboard has image)

The handler does **not** fall through to native paste (which would dump
PNG bytes into the local terminal stream). Instead it:

- Saves the PNG to `~/Downloads/wezterm-paste-<ISO timestamp>.png`.
- Replaces the clipboard with that local path.
- Shows: `📎 非 SSH 会话,图片已存到 ~/Downloads,路径已复制`.

## 5. Architecture

```
┌─────────────── macOS local ─────────────────┐         ┌─── remote linux/mac ────┐
│                                             │         │                         │
│  ┌──────────────┐    Cmd+V (with image)     │  ssh    │                         │
│  │ macOS pboard │─────┐                     │ control │                         │
│  │  (PNGf)      │     ↓                     │ master  │                         │
│  └──────────────┘  ┌────────────────┐       │  conn   │                         │
│                    │ WezTerm Lua    │       │         │                         │
│                    │ paste-handler  │───────┼────────→│  /tmp/wezterm-          │
│                    └───────┬────────┘  scp  │         │  paste-<hash>.png       │
│                            │           (new │         │                         │
│                            │            cxn)│         │                         │
│  ┌──────────────┐  pbcopy  │                │         │  Claude Code runs here  │
│  │ macOS pboard │←─────────┘                │         │  (user pastes path)     │
│  │ (now text:   │                           │         │                         │
│  │  remote path)│                           │         │                         │
│  └──────────────┘                           │         │                         │
└─────────────────────────────────────────────┘         └─────────────────────────┘
```

Everything except `scp`'s side of the wire and the resulting file is on
the local machine. The remote requires no installed component.

## 6. Components

Each component is a single-purpose unit. Pure functions wherever possible
so they can be unit-tested without spawning processes.

| # | Name                       | Input                                              | Output                                            | Responsibility |
|---|----------------------------|----------------------------------------------------|---------------------------------------------------|----------------|
| 1 | `paste-image-keymap`       | (config object)                                    | (mutates config)                                  | Binds `Cmd+V` (and `Cmd+Shift+V`) to `paste-handler`. Pure config. |
| 2 | `clipboard-probe`          | —                                                  | `{kind="image"\|"text"\|"empty", local_path?}`    | Calls `osascript` to inspect clipboard classes. If `«class PNGf»` present, runs `pngpaste` to dump PNG bytes to a `$TMPDIR/wezterm-paste-XXXX.png`. |
| 3 | `ssh-target-detector`      | `pane:get_foreground_process_info()`               | `{destination, replay_flags}` or `nil`            | Walks process tree from pane's foreground process, finds nearest `ssh` descendant, runs proper argv tokenization (see §6.1) to extract the *destination* token (skipping flags and their arguments — `-J`, `-o`, `-i`, `-p`, `-L`, etc.) **and** captures `replay_flags` — every flag/value pair from the original argv that influences connection behavior, so the uploader can faithfully reproduce the user's `ssh` invocation. |
| 4 | `uploader`                 | local PNG path + `{destination, replay_flags}`     | remote absolute path                              | Computes `sha1(file)[:8]` for filename. **Precheck**: `ssh <replay_flags> -o ControlMaster=auto -o ControlPath=… <destination> "test -e <remote_path>"`. If exit 0, skip `scp` (file with same content already there) and return. Otherwise `scp <replay_flags> -o ControlMaster=auto -o ControlPath=… <local> <destination>:<remote_path>`. Both calls reuse the existing master connection, so the precheck is a fast no-op. |
| 5 | `clipboard-writer`         | text string                                        | —                                                 | Pipes the string into `pbcopy` with `printf '%s'` (no trailing newline). |
| 6 | `paste-handler`            | (window, pane)                                     | —                                                 | Orchestrator. Calls 2→3→4→5. Handles every error branch in §7. The only component with control flow. |
| 7 | `notify`                   | message, level                                     | —                                                 | Wraps `gui_window:toast_notification(...)` and `wezterm.log_info/error`. |

### 6.1 SSH argv parsing rules

`parse_ssh_argv(argv) → {destination, replay_flags}` must follow
OpenSSH's actual flag grammar, not a naive "last token wins" heuristic.
It produces two outputs:

- **`destination`**: the user/host token the original ssh would connect to.
- **`replay_flags`**: the connection-affecting flags from the original
  argv, preserved as a list so the uploader can reproduce them verbatim.
  This matters because some flags (like `-J`, `-i`, `-p`, `-o`) are
  *only* present on the command line and are **not** visible to a fresh
  `ssh -G` lookup. Skipping the replay would make the uploader's `scp`
  take a different network path than the running interactive session.

The rule:

- **Flags that consume the next argv token (skip both flag and arg):**
  `-b -c -D -E -e -F -I -i -J -L -l -m -O -o -p -Q -R -S -W -w`
- **Boolean flags (skip just the flag):**
  `-4 -6 -A -a -C -f -G -g -K -k -M -N -n -q -s -T -t -V -v -X -x -Y -y`
- **Combined short form `-tt`, `-vvv`** — treated as boolean flag stack.
- **`--`** — everything after is non-flag; first token is the destination.
- **`flag=value` form** (e.g. `-oPort=22`) — a single token; do not
  consume the next argv element.
- The **first non-flag token after all flags are consumed** is the
  destination. Everything after it is the remote command (ignored for
  our purposes — *not* added to `replay_flags`).
- Skipped flags during destination-finding are simultaneously
  **collected into `replay_flags`** in their original token order, so a
  later `scp` invocation can pass them through unchanged.

#### Worked example

```
argv = ["ssh", "-J", "root@8.210.34.23",
              "-o", "ServerAliveInterval=30",
              "-o", "ServerAliveCountMax=3",
              "root@47.237.21.3"]

walk:
  "ssh"                       → program, skip (not in replay_flags)
  "-J", "root@8.210.34.23"    → arg-consuming flag → keep both in replay_flags
  "-o", "ServerAliveInterval=30"  → keep both in replay_flags
  "-o", "ServerAliveCountMax=3"   → keep both in replay_flags
  "root@47.237.21.3"          → first non-flag → DESTINATION ✓ (stop)

result: {
  destination  = "root@47.237.21.3",
  replay_flags = ["-J", "root@8.210.34.23",
                  "-o", "ServerAliveInterval=30",
                  "-o", "ServerAliveCountMax=3"],
}
```

The uploader will then run, e.g.:

```
ssh -J root@8.210.34.23 \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ControlMaster=auto \
    -o ControlPath=~/.ssh/cm-%r@%h:%p \
    root@47.237.21.3 \
    "test -e /tmp/wezterm-paste-a3f29c1d.png"
```

and the corresponding `scp` for the actual transfer. Both share the
ControlMaster socket with the user's interactive session, so the
network path is identical and authentication is not re-prompted.

The crucial bit is recognizing that `root@8.210.34.23` after `-J` is *not*
the destination — it's the jumphost argument. A naive "last `user@`-shaped
token" heuristic would accidentally pick the right answer here, but break
on argv like `ssh root@host echo hello` (last token is `hello`) or
`ssh -J jump host` (last token is `host`, correct, but `-J jump` is a
host too — we'd ambiguously match either).

The other crucial bit is the `replay_flags` output. Without it, the
uploader would be forced to either (a) trust `ssh -G` alone — which
ignores command-line `-J` / `-o` because those are not in any config
file — and silently take a different network path than the user's live
session, or (b) re-implement OpenSSH's effective-config logic. Capturing
the original flags and replaying them verbatim sidesteps both problems.

### Why these boundaries

- The orchestrator (#6) is the only thing that fans out to multiple
  external processes. Everything else is a single shell-out (or none).
- `ssh-target-detector` (#3) deliberately uses `ssh -G` rather than
  hand-parsing argv. Hand-parsing would miss `Match` blocks and
  `ProxyJump` chains.
- `uploader` (#4) names files by content hash. This gives free
  deduplication: the same screenshot pasted twice does not cause two
  uploads, and lets the remote `/tmp` self-cap.

## 7. Data Flow (single paste, happy path)

```
event: user presses Cmd+V in an SSH pane
│
├─→ [1] paste-handler invoked with (window, pane)
│
├─→ [2] clipboard-probe
│   │   osascript -e 'clipboard info' → check for «class PNGf»
│   │   IF not image → call default WezTerm PasteFrom("Clipboard"); RETURN
│   │   pngpaste $TMPDIR/wezterm-paste-XXXX.png
│   ↓
│   produces: local_path
│
├─→ [3] ssh-target-detector
│   │   pane:get_foreground_process_info() → walk children
│   │   find ssh process, parse argv per §6.1
│   │   IF no ssh found → see §8 "non-ssh pane" branch; RETURN
│   ↓
│   produces: ssh_target = {
│              destination  = "root@47.237.21.3",
│              replay_flags = ["-J","root@8.210.34.23",
│                              "-o","ServerAliveInterval=30", ...],
│            }
│
├─→ [4] uploader
│   │   hash = sha1(file)[:8]            # e.g. "a3f29c1d"
│   │   remote_path = "/tmp/wezterm-paste-a3f29c1d.png"
│   │
│   │   # precheck: same content already uploaded?
│   │   ssh <replay_flags> \
│   │       -o ControlMaster=auto -o ControlPath=… \
│   │       <destination> "test -e /tmp/wezterm-paste-a3f29c1d.png"
│   │   IF exit 0 → skip scp, jump straight to step 5
│   │
│   │   # otherwise, transfer (replay_flags propagated through scp too)
│   │   scp <replay_flags> \
│   │       -o ControlMaster=auto -o ControlPath=~/.ssh/cm-%r@%h:%p \
│   │       <local_path> <destination>:/tmp/wezterm-paste-a3f29c1d.png
│   │   IF non-zero → see §8 "scp fail" branch
│   ↓
│   produces: remote_path
│
├─→ [5] clipboard-writer
│   │   printf '%s' "/tmp/wezterm-paste-a3f29c1d.png" | pbcopy
│
└─→ [6] notify("📎 路径已复制到剪贴板,Cmd+V 即可粘贴", "info")
```

### Subtle invariants (encoded in tests)

- Step 5 only runs after step 4 returns success. We never overwrite the
  user's image clipboard with a path that doesn't exist on the remote.
- `pbcopy` input has no trailing newline. A trailing `\n` would cause the
  user's second `Cmd+V` to also press Return, sending the input early.
- The local PNG temp file lives in `$TMPDIR` (macOS user temp), not
  `/tmp`. macOS reaps it; we don't bookkeep it.
- The remote file is named by content hash. The uploader does an
  explicit `ssh "test -e ..."` precheck and skips `scp` when the file
  already exists, so re-pasting the same image is bandwidth-free.

## 8. Error Handling & Fallback

| Failure mode                                        | Detection                              | Behavior                                                                                                  | Toast                                                            |
|-----------------------------------------------------|----------------------------------------|-----------------------------------------------------------------------------------------------------------|------------------------------------------------------------------|
| `pngpaste` not installed                            | `which pngpaste` empty / exit 127      | Image clipboard preserved; fall through to native paste; tell user once.                                  | `❗需要 brew install pngpaste,本次未上传`                          |
| Clipboard is text / empty                           | `clipboard-probe` returns non-image    | Fall through to WezTerm native `PasteFrom("Clipboard")`.                                                  | (silent)                                                         |
| Pane is not an SSH session, but clipboard is image  | `ssh-target-detector` returns `nil`    | Save PNG to `~/Downloads/wezterm-paste-<ISO>.png`. Replace clipboard with that local path. Do NOT fall through to native paste (which would print PNG bytes). | `📎 非 SSH 会话,图片已存到 ~/Downloads,路径已复制`               |
| `ssh -G` cannot resolve host                        | exit ≠ 0 OR empty `hostname` field     | Same as "not SSH" branch above.                                                                           | `⚠️ 解析 ssh 目标失败,图片已存到 ~/Downloads`                       |
| `scp` fails (network, auth, disk full, perms)       | non-zero exit                          | Clipboard untouched (still has original PNG, user can retry). Toast shows first 200 bytes of stderr.      | `✗ 上传失败: <stderr 摘要>`                                        |
| Whole pipeline > 10s wall clock                     | Lua deadline timer                     | Kill child processes. Clipboard untouched.                                                                | `✗ 超时,剪贴板未修改`                                              |
| `pbcopy` fails                                      | non-zero exit (extremely unlikely)     | Clipboard left in indeterminate state; toast asks user to copy manually.                                  | `✗ pbcopy 失败,远端文件已传至 <path>`                              |

### Global rules

- **Never silently overwrite the clipboard on failure.** The user must be
  able to retry by pressing `Cmd+V` again.
- **Never let raw PNG bytes hit the terminal stream.** This is the
  single worst native-paste behavior in SSH today; we exist to prevent
  it.
- **Hard-dependency missing → clear, single-line install hint.** Do not
  log a stack trace.

## 9. Configuration Surface

The Lua module exposes a small config table:

```lua
image_paste.apply_to_config(config, {
    -- Override the default Cmd+V binding. Default: true.
    bind_cmd_v = true,

    -- Remote directory for uploaded files. Default: "/tmp".
    remote_dir = "/tmp",

    -- Local directory for non-SSH-pane fallback. Default: "~/Downloads".
    local_fallback_dir = "~/Downloads",

    -- Pipeline timeout in seconds. Default: 10.
    timeout_seconds = 10,
})
```

Defaults must be sane enough that no config beyond `apply_to_config(config)`
is needed for the typical user.

## 10. Testing Strategy

### Unit tests (busted, automated)

- `hash_filename(bytes)` produces 8-char lowercase hex; identical input
  → identical hash; tiny diff → different hash.
- `parse_ssh_argv(argv) → {destination, replay_flags}` for various argv shapes
  (each row asserts both outputs):
  - `ssh host` → `{destination="host", replay_flags=[]}`
  - `ssh user@host` → `{destination="user@host", replay_flags=[]}`
  - `ssh -p 22 user@host` → `{destination="user@host", replay_flags=["-p","22"]}`
  - `ssh -i ~/.ssh/id_ed25519 host cmd` → `{destination="host", replay_flags=["-i","~/.ssh/id_ed25519"]}` (note: `cmd` is the remote command; not in replay_flags)
  - `ssh -J jump host` → `{destination="host", replay_flags=["-J","jump"]}`
  - **`ssh -J root@8.210.34.23 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 root@47.237.21.3`** → `{destination="root@47.237.21.3", replay_flags=["-J","root@8.210.34.23","-o","ServerAliveInterval=30","-o","ServerAliveCountMax=3"]}`
  - `ssh -oPort=22 host` → `{destination="host", replay_flags=["-oPort=22"]}` (combined form is one token)
  - `ssh -tt host htop` → `{destination="host", replay_flags=["-tt"]}`
  - `ssh -- host` → `{destination="host", replay_flags=[]}`
  - Negative cases: `ssh-add`, `sshfs`, `ssh -V`, no ssh in tree → returns `nil`.
- `validate_remote_path(s)` rejects path separators that break shell
  quoting; ensures generated filenames are safe.
- `parse_ssh_G_output(text) → {host, port, user, identity}` handles
  multiline `key value` output and missing fields.

### Component tests (mocked subprocess, automated)

- `clipboard-probe`: mock `osascript` and `pngpaste`; verify it returns
  `{kind="image", local_path=...}` only when both succeed.
- `ssh-target-detector`: mock `pane:get_foreground_process_info()` with
  fake process trees; verify nearest-ssh-descendant logic.
- `uploader`: mock `wezterm.run_child_process`; assert exact `scp`
  argv, including ControlMaster flags.
- `paste-handler`: with all dependencies mocked, walk each branch in §8
  and assert correct toast + correct clipboard side-effect.

### Integration (optional, automated on macOS runner)

- Stand up `sshd` on `localhost`, run the full pipeline. Assert the file
  exists on `localhost:/tmp` and the local clipboard contains the path.

### Manual checklist (pre-release)

1. `Cmd+V` on plain text → native paste behavior unchanged.
2. `Cmd+V` on image into SSH pane → file at remote path; clipboard now
   has that path.
3. Same image pasted twice → second is fast (hash hit, no real upload).
4. `Cmd+V` on image into a *non-SSH* pane → file in `~/Downloads`,
   clipboard has local path.
5. `Cmd+V` on image into an SSH pane that has `tmux` + Claude Code
   running inside → upload succeeds, tmux is unaffected.
6. `Cmd+V` on image into an SSH host that uses `ProxyJump` in
   `~/.ssh/config` → upload succeeds via the jumphost.
6b. `Cmd+V` on image into an SSH session launched with inline `-J` and
   multiple `-o` flags
   (`ssh -J root@jump -o ServerAliveInterval=30 root@final`) → host
   correctly resolved to `root@final`, not the `-J` arg, upload succeeds.
7. Disconnect network mid-paste → clipboard unchanged, toast shows
   error.
8. Uninstall `pngpaste`, paste image → clear "brew install pngpaste"
   toast; clipboard preserved.

Items 1–8 must pass for V1 to ship.

## 11. Out of Scope (Explicit YAGNI)

| Item                                                         | Why excluded                                                                |
|--------------------------------------------------------------|------------------------------------------------------------------------------|
| Bidirectional clipboard sync (remote → local)                | Not in user's workflow; OSC 52 already exists for text.                     |
| Video / PDF / arbitrary binaries                             | Claude Code's main consumption is images; revisit on real demand.            |
| Image compression / resize                                   | scp transfers raw bytes fine on typical links.                              |
| Inline imgcat / sixel preview in the local terminal          | WezTerm already supports image protocols; not on this feature's path.       |
| Multi-host fan-out                                           | No use case.                                                                 |
| Remote daemon / systemd unit                                 | Remote zero-deploy is a hard goal.                                          |
| Modifying WezTerm Rust core / upstream PR                    | V1 is Lua-only; revisit only after real-world stability.                    |
| Auto-cleanup of remote `/tmp/wezterm-paste-*`                | OS handles `/tmp`; user can `rm` if they care.                              |
| Windows / Linux client                                       | Uses pngpaste / pbcopy / osascript; macOS-only by construction.             |
| iTerm2 / Ghostty / Alacritty / Kitty adapters                | WezTerm-only by construction.                                               |
| Synthesizing the second paste keystroke                      | User explicitly wants to paste manually.                                    |

## 12. Deliverables

1. **`wezterm-image-paste.lua`** — single Lua module (~200–300 lines),
   `require`-able from `~/.wezterm.lua`. Exposes `apply_to_config`.
2. **`README.md`** — three-step install: brew install pngpaste, copy
   Lua module, add `require` line. Plus the recommended `ControlMaster`
   block for `~/.ssh/config`.
3. **`spec/`** — busted unit tests for the pure-function components
   listed in §10 ("Unit tests").
4. **`spec/components/`** — mocked-subprocess tests for §10 ("Component
   tests").
5. **`docs/manual-test-checklist.md`** — the 8-item list from §10
   ("Manual checklist").
6. *(Optional, not blocking V1)* a short demo recording showing
   `Cmd+V` → toast → second `Cmd+V` → Claude Code receiving the path.

## 13. Open Questions

None at design-approval time. Any new question discovered during
implementation should be raised against the implementation plan, not
this spec.

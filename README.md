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

## How it routes pastes

When you press `Cmd+V`, the handler detects what's in your clipboard and what
pane is active, then chooses one of these paths:

- **`passthrough`**: Clipboard holds text or is empty → native paste runs
- **`uploaded`**: Clipboard holds image + pane is SSH → image uploaded to remote, clipboard now holds remote path
- **`fallback_local`**: Clipboard holds image + pane is not SSH → image saved to `~/Downloads`, clipboard now holds local path
- **`missing_pngpaste`**: Clipboard holds image but `pngpaste` not installed → toast tells you to install it
- **`probe_failed`**: `osascript` itself failed → toast shows stderr
- **`ssh_fail`**: scp upload failed → clipboard preserved (image still there to retry)
- **`fallback_failed`**: local save to `~/Downloads` failed → clipboard preserved

## Caveats

- macOS only (uses `pbcopy`, `osascript`, `pngpaste`).
- WezTerm only (uses `wezterm.action_callback` and pane process info).
- The 10s timeout is best-effort; it sets `ssh -o ConnectTimeout=10`
  but does not deadline a stuck transfer over a working but slow link.
- Uploaded files are not auto-cleaned. Your remote `/tmp` policy
  handles them.

### How it works under the hood

- **SSH detection**: Detects SSH from the active pane's foreground process tree
  (depth-first search for a process named `ssh`). Handles `-J jumphost`,
  `-o key=val`, and other flags seamlessly.
- **Flag replay**: Extracts SSH argv flags (identity files, jump hosts, user,
  port, etc.) and replays them into both `ssh` precheck and `scp` upload
  commands, so the file takes the same network path as your interactive session.
- **Content addressing**: Remote filename is `sha1[:8]` of the image bytes,
  so re-pasting the same screenshot is a no-op (precheck sees the file already
  exists, skips the upload).
- **Connection multiplexing**: If you have `ControlMaster` configured in
  `~/.ssh/config`, the uploader uses it automatically (via hardcoded flags
  `ControlMaster=auto`, `ControlPath`, `ControlPersist=10m`). The first
  paste opens a master connection; subsequent pastes reuse it. Without user
  config, still works—just opens a fresh connection each time.

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| Toast: `❗需要 brew install pngpaste` | `pngpaste` not on PATH |
| Toast: `✗ 上传失败: …` | Network or auth issue. Run the same `ssh` command manually to debug. |
| `Cmd+V` does nothing visible | Pane is not SSH and clipboard is text — native paste should still work. |

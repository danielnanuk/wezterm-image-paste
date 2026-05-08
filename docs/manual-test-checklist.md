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

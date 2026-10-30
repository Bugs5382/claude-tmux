# claude-tmux 🪟

> 🧭 tmux sessions for Claude Code on macOS and Linux: hourly snapshots and a restore that resumes each Claude conversation.

I run two tmux sessions: `OPS` for the operator, and `CODING` with one window per project, each
with Claude panes in it. A reboot or a crash used to throw all of that away. claude-tmux saves every session, window and pane
once an hour, and `tmux-restore` brings them back with their layouts and folders. 🔁 **Claude panes
pick up where they left off:** each one runs `claude --resume <id>` for the conversation it had at the
last save.

## ✨ Highlights

- 💾 **Hourly snapshots:** a launchd agent (macOS) or a systemd user timer (Linux) runs `tmux-save` every hour and keeps the newest 24.
- 🚪 **Closing sticks:** tmux saves right after a session or window closes, so a restore doesn't bring it back.
- 🔁 **Claude resumes:** a SessionStart/SessionEnd hook tags each pane with its Claude session, and the restore resumes it.
- 📐 **Exact layouts:** sessions, windows, pane splits and folders come back as they were, names with spaces included.
- 🛡️ **Running sessions are kept:** `tmux-restore` rebuilds only the saved sessions that aren't running and leaves the rest alone.
- 🖱️ **Mouse and clipboard:** trackpad scrolling, drag to copy to the clipboard (macOS, Wayland, X11, or your own terminal over SSH), click to focus.

## 🧰 Before you start

- macOS, or Linux with systemd (Ubuntu, Debian, Fedora and the like).
- tmux 3.x and `jq`: `brew install tmux` on macOS (which ships `jq` at `/usr/bin/jq`), or
  `sudo apt install tmux jq` on Ubuntu.
- [go-task](https://taskfile.dev) for the `task` commands, or run the scripts with `bash` directly.

## 📦 Install

1. Clone the repo and run the installer from it:

   ```bash
   git clone https://github.com/Bugs5382/claude-tmux.git
   cd claude-tmux
   bash install.sh
   ```

   It links `tmux.conf` to `~/.tmux.conf`, `bin/tmux-save` and `bin/tmux-restore` into
   `~/.local/bin/`, and the hook to `~/.claude/hooks/tmux-claude-tag.sh`. Then it starts the hourly
   save: on macOS it writes `~/Library/LaunchAgents/com.bugs5382.tmux-save.plist` and loads it, and on
   Linux it installs a systemd user timer (see [Linux](#-linux)). A file that is already at one of
   those paths (not a link) is moved aside to `<name>.bak.<timestamp>` first. Running it again is
   safe. Keep the clone where it is: the links point into it.

2. Add the two hook entries it prints to the `"hooks"` block of `~/.claude/settings.json`. The
   installer never edits that file:

   ```json
   "SessionStart": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/tmux-claude-tag.sh"}]}],
   "SessionEnd":   [{"hooks": [{"type": "command", "command": "~/.claude/hooks/tmux-claude-tag.sh"}]}]
   ```

   If `SessionStart` already has entries, add the command to its list instead of a second key.

3. If the installer says `~/.local/bin` is not on your PATH, add this to the file it names
   (`~/.zshrc` on macOS, your shell's rc file on Linux) and open a new terminal:

   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```

## 🚀 Usage

Terminal opens a plain shell; tmux only starts when you start it:

```bash
tmux-start
```

`tmux-start` creates `OPS` if it isn't running, starts Claude in it, and attaches to it. A running
`OPS` is left as it is. It and `tmux-restore` both ask
whether you are on SSH before they attach: yes sets the prefix to Ctrl-a, because Ctrl-b gets in the
way over SSH, and no sets it to Ctrl-b. Pressing Enter takes what the connection says. Press the
prefix twice to send the key itself. To change it later, run `tmux-prefix ssh` or `tmux-prefix local`.

`tmux-start` also checks once, in the background, whether GitHub has a newer release than your clone.
If so, a message in tmux says which one; it installs nothing, and you update with `git pull` in the
clone, then `bash install.sh`. Your version is the clone's nearest `v*` tag, so a clone with no tags
(`git clone --depth 1`) stays quiet, and so does a failed check. Each check's result is in
`update-check.log` in the state folder. Nothing else checks: not `tmux-restore`, `tmux-save` or the hook.

Save now, list the snapshots, and restore:

```bash
tmux-save
tmux-restore --list
tmux-restore
tmux-restore --no-attach
```

`tmux-restore [--no-attach] [snapshot.json]` takes an optional snapshot path; without one it uses
`latest.json`. It works whether or not tmux is running. Each saved session that is already running
(same name) is left as it is (`kept <name> (already running)`), and every other one is rebuilt.

A session or window you close stays closed: `tmux.conf` hooks `session-closed` and
`window-unlinked` and runs `tmux-save --on-close` in the background, so `latest.json` drops it
right away instead of at the next hourly save. That mode saves the server that ran the hook, logs
to `save.log` instead of the pane, and adds `~/.local/bin` and Homebrew to PATH. One save runs at a
time: a save that starts while another is running leaves a pending mark and exits, and the running
save goes again until no mark is left, so killing a session with many windows ends in one current
snapshot. `tmux-restore` sets the server option `@claude_tmux_restoring` while it builds sessions,
and the hooks skip saving while it is set. Closing the last session ends the server before a save
can run, so that session is still in `latest.json`.

Then it takes you to `OPS`, or to the snapshot's first session when there is no `OPS`: outside tmux
it attaches, and inside tmux it switches your client. With `--no-attach`, or when stdin or stdout is
not a terminal (a pipe, launchd, the tests), it only restores and prints the `tmux attach` command.

Stop everything, or stop it and bring it straight back with each Claude pane resumed:

```bash
tmux-stop
tmux-restart
```

Use these instead of closing windows by hand, because closing sticks. `tmux-stop` saves once,
then stops the server, so `latest.json` holds every session and `tmux-restore`
brings them all back. Run `tmux-restart [--no-attach]` from a terminal outside tmux: inside tmux it
would die with the server, so it exits 64 and tells you. Panes keep only their Claude conversation;
anything else running in a pane, such as a dev server, stops and comes back as a plain shell.

Exit codes for `tmux-restore`:

| Code | Meaning |
|---|---|
| 0 | restored (running sessions kept) |
| 2 | the snapshot is missing or not valid JSON; nothing was changed |
| 3 | at least one session could not be fully rebuilt; it is named on stderr, the other sessions were still restored, and it does not attach |

The hourly save and the close hooks log to `~/.local/state/tmux/save.log`. To check that the
hourly agent is loaded on macOS:

```bash
launchctl print gui/$(id -u)/com.bugs5382.tmux-save
```

## 🐧 Linux

On Linux the hourly save is a systemd user timer instead of launchd. `install.sh` copies
`systemd/tmux-save.service` and `systemd/tmux-save.timer` into `~/.config/systemd/user/` (or
`$XDG_CONFIG_HOME/systemd/user/`), reloads your user manager and enables the timer. It first runs
15 minutes after boot, then every hour, and catches up after the machine was off. Check it:

```bash
systemctl --user list-timers tmux-save.timer
systemctl --user start tmux-save.service   # save now, the way the timer does
```

- 🔌 **No user manager:** in a container, or a shell with no login session, `install.sh` still links
  and writes everything, then tells you to run `systemctl --user enable --now tmux-save.timer` once
  you are in a normal session.
- 🛰️ **Over SSH:** your user manager, and the timer with it, stops when your last login ends. To
  keep saving while you are logged out, turn on lingering once:
  `sudo loginctl enable-linger "$USER"`.
- 📋 **Clipboard:** `tmux.conf` copies with `wl-copy` in a Wayland session (`sudo apt install
  wl-clipboard`) and `xclip` in an X11 one (`sudo apt install xclip`). With neither, as over SSH, it
  turns on tmux's OSC 52 support, so a copy lands in the clipboard of the terminal you are typing in
  (most modern terminals allow it). tmux decides when it loads its config, so a server started over
  SSH keeps using OSC 52 until it restarts.

## 🤖 How Claude panes come back

The hook runs on every Claude SessionStart (including after `/clear`) and sets the pane option
`@claude_session` to that session's ID; SessionEnd clears it. Only the pane's own Claude (the
pane's command, or one started from the pane's shell) changes the tag, so a `claude -p` run from a
script or a tool inside that Claude leaves it alone. `tmux-save` records the tag, and
`tmux-restore` types `claude --resume <id>` into that pane's shell, so the shell is still there when
Claude exits. Panes without a tag get a plain shell in their folder.

If Claude crashed without a SessionEnd, the pane keeps a stale tag. On restore Claude says it can't
find the session and exits; the shell is still yours. A folder that no longer exists falls back to
`~/Code`, then `~`.

Pane contents (scrollback) are not saved.

## 🖱️ Mouse and clipboard

`tmux.conf` turns mouse mode on: the trackpad scrolls a pane's history, clicking a pane focuses it,
and dragging a selection copies it to the clipboard (`pbcopy` on macOS; Linux is under
[Linux](#-linux)). In copy mode, `y` copies too. History
keeps 50,000 lines, windows and panes count from 1, and the status bar shows the session name.

With mouse mode on, Terminal hands clicks to tmux. If Cmd-click on a link does nothing, hold Fn
while clicking so Terminal handles it.

## 🗂️ State and settings

Snapshots live in `~/.local/state/tmux/snapshots/` as `<UTC time>.json`, with `latest.json` pointing
at the newest. A save writes to a temporary file and renames it, so `latest.json` is always complete.
Each save prunes to the newest 24. `save.lock` (the running save's pid) and `save.pending` sit
next to `snapshots/` while a save runs; a lock whose pid is gone is cleared by the next save.

| Variable | Default | Used for |
|---|---|---|
| `TMUX_STATE_DIR` | `~/.local/state/tmux` | where snapshots go |
| `TMUX_SAVE_KEEP` | `24` | how many snapshots to keep |
| `TMUX_SOCKET_NAME` | `default` | the tmux socket (`tmux -L`) |
| `TMUX_CONFIG` | unset | a config file passed as `tmux -f` |
| `CLAUDE_TMUX_NO_LAUNCHCTL` | unset | when set, `install.sh` skips `launchctl` (macOS) |
| `CLAUDE_TMUX_NO_SYSTEMCTL` | unset | when set, `install.sh` writes the units but skips `systemctl` (Linux) |
| `CLAUDE_TMUX_OS` | `uname -s` | which install path to take, `Darwin` or `Linux`; the tests set it |
| `CLAUDE_TMUX_RELEASE_URL` | the GitHub latest-release API for this repo | where `tmux-start` looks for a newer release; the tests set it |

## 🧹 Uninstall

On macOS:

```bash
launchctl bootout gui/$(id -u)/com.bugs5382.tmux-save
rm ~/Library/LaunchAgents/com.bugs5382.tmux-save.plist
rm ~/.tmux.conf ~/.local/bin/tmux-save ~/.local/bin/tmux-restore ~/.local/bin/tmux-start ~/.local/bin/tmux-prefix ~/.local/bin/tmux-stop ~/.local/bin/tmux-restart ~/.claude/hooks/tmux-claude-tag.sh
```

On Linux:

```bash
systemctl --user disable --now tmux-save.timer
rm ~/.config/systemd/user/tmux-save.service ~/.config/systemd/user/tmux-save.timer
systemctl --user daemon-reload
rm ~/.tmux.conf ~/.local/bin/tmux-save ~/.local/bin/tmux-restore ~/.local/bin/tmux-start ~/.local/bin/tmux-prefix ~/.local/bin/tmux-stop ~/.local/bin/tmux-restart ~/.claude/hooks/tmux-claude-tag.sh
```

Then remove the two hook entries from `~/.claude/settings.json`. Snapshots stay in
`~/.local/state/tmux/` until you remove them.

## 🛠 Develop

```bash
task lint    # shellcheck over every script
task test    # tests/run.sh: every tests/*.test.sh, each in a temporary HOME
task e2e     # the Linux end-to-end check in a systemd Ubuntu container (needs docker)
```

The tests run their own tmux server on a private socket (`claude-tmux-test-<pid>`) and never touch
the one you are using, your `~/.tmux.conf`, launchd or systemd: stand-ins for `launchctl` and
`systemctl` record what the installer asked for, and a fake `claude` on PATH records how restore
called it. Both install paths are tested on every OS (`CLAUDE_TMUX_OS`). `task e2e` boots Ubuntu
with systemd in a container (`ci/linux.Dockerfile`) and, as a normal user, installs, saves through
the real timer's service, closes a window, kills the server and restores it; CI runs it on every
pull request.

## ⚖️ License

MIT (c) 2026 Shane

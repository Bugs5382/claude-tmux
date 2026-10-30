# AGENTS.md - claude-tmux

Guide for AI agents working in this repository. Pair with `CLAUDE.md` (the working agreement and
hook-enforced rules). Keep this file current when the build, layout, or public API changes.

## What this is

tmux sessions for Claude Code on macOS and Linux: hourly snapshots and a restore that resumes each Claude conversation.

Two bash scripts, a Claude hook, a tmux.conf, and an hourly job: a launchd agent on macOS or a systemd user timer on Linux. `tmux-save` writes a
JSON snapshot of every tmux session, window and pane; `tmux-restore` rebuilds them and types
`claude --resume <id>` into panes the hook tagged with `@claude_session`. Two things to know before
changing it:

- Tests must never reach the real tmux server or the real HOME. They use the private socket and
  `TMUX_TMPDIR` from `tests/lib.sh` and the temporary HOME from `tests/run.sh`; `install.sh` runs in
  tests only with `CLAUDE_TMUX_OS` set and `CLAUDE_TMUX_NO_LAUNCHCTL=1` or the fake `launchctl` and
  `systemctl` from `tests/fixtures/` first on PATH.
- launchd and systemd run `tmux-save` with a minimal environment (no locale, their own PATH from the
  plist or unit), so `tmux-save` calls `tmux -u` and exits 127 when tmux is missing.
- macOS behaviour must not change when Linux changes: the `pbcopy` bindings and the launchd path are
  tested on every OS.

## Layout

- `bin/tmux-save`, `bin/tmux-restore`, `bin/tmux-stop`, `bin/tmux-restart` - the commands (no `.sh`: they are linked onto PATH)
- `hooks/tmux-claude-tag.sh` - SessionStart/SessionEnd hook that sets or clears `@claude_session`
- `tmux.conf` - mouse, clipboard (pbcopy, wl-copy, xclip or OSC 52, chosen at load), base indexes,
  and the close hooks that run `tmux-save --on-close`; linked to `~/.tmux.conf`
- `launchd/com.bugs5382.tmux-save.plist` - hourly agent template (`__HOME__` is filled in on install)
- `systemd/tmux-save.service`, `systemd/tmux-save.timer` - the hourly job on Linux (`%h` is the home folder)
- `install.sh` - links everything into place, starts the hourly job for the OS, prints the settings snippet
- `ci/` - the Linux end-to-end check: `linux.Dockerfile` (Ubuntu with systemd as PID 1),
  `linux-e2e-run.sh` (builds, boots, runs) and `linux-e2e.sh` (the check, as a normal user)
- `tests/` - `run.sh` runner, `lib.sh` helpers (private tmux server), one `*.test.sh` per area,
  `fixtures/` (hook payloads, fake `claude`, `launchctl` and `systemctl`)

## Build, test, lint

<!-- The exact commands. Pull these from package.json scripts (npm), the Taskfile (Go/Task), or
pyproject (Python) so they stay accurate. -->

- Build: none
- Test: `task test` (needs tmux and jq; CI installs tmux from apt)
- Lint: `task lint` (shellcheck over `*.sh`, `bin/*` and `tests/fixtures/fake-*`)
- Linux end-to-end: `task e2e` (needs docker; CI runs it too)
- Install: `task install`

## Logging

Follow the logging rules in `CLAUDE.md`. In short:

- Log generously: entry and exit of significant operations, decisions and branches, retries, state
  changes, external calls (target, duration, outcome), and every error with its context.
- Levels: `trace` for step-by-step detail, `debug` for flow, `info` for lifecycle, `warn` and
  `error` for problems. The environment filters the volume, so err on the side of too much.
- Environments: local dev `trace` with `LOG_FORMAT=console` (never JSON), dev cluster `debug`,
  qa/staging `info`, production `error`. Every cluster environment logs JSON. Set levels through
  `LOG_LEVEL` and `LOG_FORMAT`, never in code; local settings live in the run target or
  `.env.example`.
- Never log secrets, tokens, or personal data, not even at `trace`. Log an opaque or keyed ID.

## Conventions and gotchas

- See `CLAUDE.md` for the branch/commit/PR rules; they are enforced by the git hooks in
  `.claude/hooks` (run `bash .claude/hooks/install.sh` once per clone).
- Open every PR as a draft. CI skips drafts, so run the full checks locally, push once they pass,
  and mark the PR ready when the work is finished; see CLAUDE.md "CI and Actions minutes".
- The layout differs from the claude-code hook baseline in CLAUDE.md: this repo ships commands, a
  tmux.conf and a launchd agent alongside the hook, and `install.sh` links files instead of copying.
- Script comments may not name the CLI product ("Claude Code"); the pre-commit hook allows it only
  in Markdown.
- The close hooks run `tmux-save --on-close` from inside the server. It takes the socket from
  `$TMUX`, not `TMUX_SOCKET_NAME`, and logs to `save.log`. `tmux-restore` sets
  `@claude_tmux_restoring` so its placeholder window kills don't save a half-built server; anything
  new in restore that closes windows needs to stay inside that flag. `tests/close.test.sh` covers it.
- `window_layout` strings carry pane IDs, so tests compare layout geometry, not the raw string.

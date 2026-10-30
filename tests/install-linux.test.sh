#!/usr/bin/env bash
set -euo pipefail
# install.sh writes into $HOME: only ever run it in the temporary HOME from tests/run.sh.
case "$(basename "$HOME")" in test-home.*) ;; *) echo "FAIL: HOME is not a test home: $HOME" >&2; exit 1 ;; esac
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
export CLAUDE_TMUX_OS=Linux SHELL=/bin/bash
unset CLAUDE_TMUX_NO_SYSTEMCTL XDG_CONFIG_HOME
mkdir -p "$HOME/bin"
cp "$ROOT/tests/fixtures/fake-systemctl" "$HOME/bin/systemctl"
export PATH="$HOME/bin:$PATH" SYSTEMCTL_LOG="$HOME/systemctl.log"
# Never let the real systemctl run from a test.
[ "$(command -v systemctl)" = "$HOME/bin/systemctl" ] || fail "fake systemctl not first on PATH"

printf 'my own config\n' > "$HOME/.tmux.conf"
out="$(bash "$ROOT/install.sh")" || fail "install exit $?"
for l in .tmux.conf .local/bin/tmux-save .local/bin/tmux-restore .claude/hooks/tmux-claude-tag.sh; do
  [ -L "$HOME/$l" ] || fail "$l not linked"
done
bak="$(find "$HOME" -maxdepth 1 -name '.tmux.conf.bak.*' | head -1)"
[ -n "$bak" ] && [ "$(cat "$bak")" = "my own config" ] || fail "existing ~/.tmux.conf not backed up"
[ ! -e "$HOME/Library" ] || fail "wrote a launchd agent on Linux"

units="$HOME/.config/systemd/user"
svc="$units/tmux-save.service"; tmr="$units/tmux-save.timer"
[ -f "$svc" ] && [ ! -L "$svc" ] || fail "service not written"
[ -f "$tmr" ] && [ ! -L "$tmr" ] || fail "timer not written"
grep -qx 'Type=oneshot' "$svc" || fail "service type"
grep -qx 'ExecStart=%h/.local/bin/tmux-save' "$svc" || fail "service ExecStart"
grep -q '^Environment=PATH=%h/.local/bin:' "$svc" || fail "service PATH"
grep -qx 'Environment=LANG=C.UTF-8' "$svc" || fail "service locale"
grep -qx 'StandardOutput=append:%h/.local/state/tmux/save.log' "$svc" || fail "service log"
grep -qx 'OnUnitActiveSec=1h' "$tmr" || fail "timer interval"
grep -qx 'Persistent=true' "$tmr" || fail "timer persistent"
grep -qx 'WantedBy=timers.target' "$tmr" || fail "timer install target"
[ -d "$HOME/.local/state/tmux" ] || fail "state dir (the service log) not created"

grep -qx -- '--user daemon-reload' "$SYSTEMCTL_LOG" || fail "no daemon-reload: $(cat "$SYSTEMCTL_LOG")"
grep -qx -- '--user enable --now tmux-save.timer' "$SYSTEMCTL_LOG" || fail "timer not enabled: $(cat "$SYSTEMCTL_LOG")"
grep -q 'tmux-save.timer' <<<"$out" || fail "no word about the timer"
{ grep -q '"SessionStart"' <<<"$out" && grep -q '"SessionEnd"' <<<"$out"; } || fail "snippet"
# shellcheck disable=SC2088 # the literal text install.sh prints
grep -qF "add this to ~/.bashrc" <<<"$out" || fail "PATH note does not name the bash rc file: $out"
bash "$ROOT/install.sh" >/dev/null || fail "re-install"

# XDG_CONFIG_HOME moves the unit folder.
XDG_CONFIG_HOME="$HOME/xdg" bash "$ROOT/install.sh" >/dev/null
[ -f "$HOME/xdg/systemd/user/tmux-save.timer" ] || fail "XDG_CONFIG_HOME ignored"

# No user manager: everything is still linked and written, and it says how to start the timer.
: > "$SYSTEMCTL_LOG"
out="$(SYSTEMCTL_DOWN=1 bash "$ROOT/install.sh")" || fail "install without a user manager exit $?"
grep -q 'enable --now tmux-save.timer' <<<"$out" || fail "no hint to enable later: $out"
! grep -q -- '--now' "$SYSTEMCTL_LOG" || fail "tried to enable without a user manager"

# CLAUDE_TMUX_NO_SYSTEMCTL: units written, systemctl never called.
: > "$SYSTEMCTL_LOG"
CLAUDE_TMUX_NO_SYSTEMCTL=1 bash "$ROOT/install.sh" >/dev/null
[ ! -s "$SYSTEMCTL_LOG" ] || fail "called systemctl with CLAUDE_TMUX_NO_SYSTEMCTL: $(cat "$SYSTEMCTL_LOG")"

# An OS it doesn't know: stop before touching anything.
rm -rf "$HOME/other" && mkdir -p "$HOME/other"
set +e; err="$(HOME="$HOME/other" CLAUDE_TMUX_OS=Plan9 bash "$ROOT/install.sh" 2>&1)"; rc=$?; set -e
[ "$rc" -ne 0 ] || fail "unknown OS accepted"
grep -q 'Plan9' <<<"$err" || fail "unknown OS message: $err"
[ -z "$(ls -A "$HOME/other")" ] || fail "unknown OS wrote files: $(ls -A "$HOME/other")"

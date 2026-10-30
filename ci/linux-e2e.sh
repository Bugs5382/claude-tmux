#!/usr/bin/env bash
# End-to-end check on Linux, run as a normal user inside ci/linux.Dockerfile: install with the real
# systemd user manager, take a snapshot through the timer's service, close a window, kill the
# server and restore it. Needs /src (the checkout, read-only) and XDG_RUNTIME_DIR.
set -euo pipefail
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }

step "install from a copy of the checkout"
cp -R /src "$HOME/claude-tmux"
bash "$HOME/claude-tmux/install.sh"
export PATH="$HOME/.local/bin:$PATH"
[ "$(systemctl --user is-enabled tmux-save.timer)" = enabled ] || fail "timer not enabled"
[ "$(systemctl --user is-active tmux-save.timer)" = active ] || fail "timer not active"
systemctl --user list-timers tmux-save.timer --no-pager

step "a fake claude records how restore resumes it"
cat > "$HOME/.local/bin/claude" <<'EOT'
#!/bin/sh
echo "$*" >> "$HOME/claude-calls"
EOT
chmod +x "$HOME/.local/bin/claude"

step "sessions to save"
mkdir -p "$HOME/proj a" "$HOME/b"
tmux new-session -d -s OPS -c "$HOME/proj a"
tmux new-session -d -s CODING -n WEB -c "$HOME/b"
tmux new-window -t CODING -n API -c "$HOME/proj a"
tmux split-window -t CODING:API -c "$HOME/b"
tmux new-window -t CODING -n SCRATCH -c "$HOME/b"
tmux set -p -t CODING:API.2 @claude_session sess-linux-1
[ "$(tmux show -gv mouse)" = on ] || fail "tmux.conf from the install not loaded"
tmux list-keys -T copy-mode | grep -q 'copy-selection-and-cancel' || fail "no OSC 52 copy binding"
[ "$(tmux show -sv set-clipboard)" = on ] || fail "set-clipboard is not on"

step "snapshot through the systemd service"
systemctl --user start tmux-save.service
snap="$HOME/.local/state/tmux/snapshots/latest.json"
[ -f "$snap" ] || fail "the service wrote no snapshot"
grep -q 'saved 5 panes' "$HOME/.local/state/tmux/save.log" || fail "save.log: $(cat "$HOME/.local/state/tmux/save.log")"
[ "$(jq -r '[.sessions[].name] | sort | join(",")' "$snap")" = CODING,OPS ] || fail "sessions in snapshot"

step "closing a window sticks"
tmux kill-window -t CODING:SCRATCH
for _ in $(seq 1 50); do
  [ "$(jq '[.sessions[].windows[]] | length' "$snap")" = 3 ] && break
  sleep 0.1
done
[ "$(jq -r '.sessions[] | select(.name == "CODING") | [.windows[].name] | join(",")' "$snap")" = WEB,API ] \
  || fail "closed window still saved: $(jq -c . "$snap")"

step "kill the server and restore"
tmux kill-server
sleep 0.5
tmux-restore --no-attach
[ "$(tmux list-sessions -F '#{session_name}' | sort | paste -sd, -)" = CODING,OPS ] || fail "sessions after restore"
[ "$(tmux list-windows -t CODING -F '#{window_name}' | paste -sd, -)" = WEB,API ] || fail "windows after restore"
[ "$(tmux display -p -t CODING:API '#{window_panes}')" = 2 ] || fail "pane count after restore"
[ "$(tmux display -p -t OPS: '#{pane_current_path}')" = "$HOME/proj a" ] || fail "folder after restore"
for _ in $(seq 1 50); do grep -q 'sess-linux-1' "$HOME/claude-calls" 2>/dev/null && break; sleep 0.1; done
grep -qx -- '--resume sess-linux-1' "$HOME/claude-calls" || fail "claude not resumed: $(cat "$HOME/claude-calls" 2>/dev/null)"
tmux kill-server

printf '\nlinux end-to-end: ok\n'

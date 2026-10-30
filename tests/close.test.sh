#!/usr/bin/env bash
set -euo pipefail
. "$ROOT/tests/lib.sh"

snap="$TMUX_STATE_DIR/snapshots/latest.json"
log="$TMUX_STATE_DIR/save.log"
sessions() { jq -r '[.sessions[].name] | join(" ")' "$snap"; }
windows() { jq -r --arg s "$1" '[.sessions[] | select(.name == $s) | .windows[].name] | join(" ")' "$snap"; }
# The hooks save in the background; poll until the snapshot shows the expected state.
wait_for() {
  local i
  for (( i = 0; i < 50; i++ )); do
    if [ "$("$1" "${@:3}")" = "$2" ]; then return 0; fi
    sleep 0.2
  done
  fail "timed out waiting for $1 ${*:3}: expected [$2] got [$("$1" "${@:3}")]"
}

# The server gets tmux-save on PATH but not TMUX_SOCKET_NAME: the hook has to find its own socket.
env -u TMUX_SOCKET_NAME PATH="$BIN:$PATH" tmux -L "$TMUX_SOCKET_NAME" -f /dev/null new-session -d -s KEEP -n main
t source-file "$ROOT/tmux.conf" || fail "tmux.conf has errors"
t new-window -d -t KEEP -n side
t new-window -d -t KEEP -n extra
t new-session -d -s GONE
"$BIN/tmux-save" >/dev/null
assert_eq "$(sessions)" "GONE KEEP" "sessions before the close"

# closing a session saves without a manual tmux-save
t kill-session -t GONE
wait_for sessions "KEEP"

# closing a window saves too
t kill-window -t KEEP:side
wait_for windows "main extra" KEEP

# hook output goes to the log, not to a pane
grep -q 'tmux-save: saved' "$log" || fail "save.log has no on-close save: $(cat "$log" 2>/dev/null)"

# a burst of closes coalesces, and the last save still sees the final state
for s in B1 B2 B3 B4; do t new-session -d -s "$s"; t new-window -d -t "$s"; done
"$BIN/tmux-save" >/dev/null
assert_eq "$(sessions)" "B1 B2 B3 B4 KEEP" "sessions before the burst"
for s in B1 B2 B3 B4; do t kill-session -t "$s"; done
wait_for sessions "KEEP"
for (( i = 0; i < 50; i++ )); do [ -e "$TMUX_STATE_DIR/save.lock" ] || break; sleep 0.2; done
[ ! -e "$TMUX_STATE_DIR/save.lock" ] || fail "save.lock left behind"
[ ! -e "$TMUX_STATE_DIR/save.pending" ] || fail "save.pending left behind"

# restore kills a placeholder window per session; that must not trigger saves
jq '.sessions += [{name: "BACK", windows: [{index: 1, name: "w", layout: .sessions[0].windows[0].layout, active: true,
     panes: [{index: 1, cwd: env.HOME, active: true, claude_session: null}]}]}]' "$snap" > "$HOME/restore.json"
before=$(wc -l < "$log")
"$BIN/tmux-restore" --no-attach "$HOME/restore.json" >/dev/null
t has-session -t "=BACK" || fail "restore did not rebuild BACK"
sleep 2
assert_eq "$(wc -l < "$log")" "$before" "save.log lines after a restore"
assert_eq "$(t show -gqv @claude_tmux_restoring)" "" "restoring flag cleared"

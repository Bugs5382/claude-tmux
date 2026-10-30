#!/usr/bin/env bash
set -euo pipefail
. "$ROOT/tests/lib.sh"

snap="$TMUX_STATE_DIR/snapshots/latest.json"
sessions() { jq -r '[.sessions[].name] | join(" ")' "$snap"; }
windows() { jq -r --arg s "$1" '[.sessions[] | select(.name == $s) | .windows[].name] | join(" ")' "$snap"; }
mkdir -p "$HOME/bin"
cp "$ROOT/tests/fixtures/fake-claude" "$HOME/bin/claude"
export PATH="$BIN:$HOME/bin:$PATH" CLAUDE_CALLS="$HOME/calls.txt"
: > "$CLAUDE_CALLS"

# nothing running is not an error
"$BIN/tmux-stop" | grep -q 'not running' || fail "stop with no server"

# The server runs the real close hooks: a stop must not let them shrink the snapshot.
tmux -L "$TMUX_SOCKET_NAME" -f /dev/null new-session -d -s OPS -n main
t source-file "$ROOT/tmux.conf" || fail "tmux.conf has errors"
t new-window -d -t OPS -n side
t new-session -d -s CODING -n work
t set -p -t CODING:work @claude_session sess-7
mkdir -p "$TMUX_STATE_DIR/snapshots"
before=$(find "$TMUX_STATE_DIR/snapshots" -name '*Z.json' | wc -l)

"$BIN/tmux-stop" >/dev/null
if t has-session 2>/dev/null; then fail "server still running after stop"; fi
sleep 1
assert_eq "$(sessions)" "CODING OPS" "sessions after stop"
assert_eq "$(windows OPS)" "main side" "windows after stop"
after=$(find "$TMUX_STATE_DIR/snapshots" -name '*Z.json' | wc -l)
assert_eq "$(( after - before ))" 1 "snapshots written by a stop"

# restart brings everything back and resumes the Claude panes
"$BIN/tmux-restart" --no-attach >/dev/null
assert_eq "$(t list-sessions -F '#{session_name}' | sort | paste -sd, -)" "CODING,OPS" "sessions after restart"
for (( i = 0; i < 50; i++ )); do grep -q 'sess-7' "$CLAUDE_CALLS" && break; sleep 0.1; done
grep -q 'sess-7' "$CLAUDE_CALLS" || fail "restart did not resume Claude: $(cat "$CLAUDE_CALLS")"

# restart on a running server saves it first, so nothing added since the last save is lost
t new-window -d -t OPS -n added
"$BIN/tmux-restart" --no-attach >/dev/null
t list-windows -t OPS -F '#{window_name}' | grep -qx added || fail "restart lost a window added since the last save"

# inside tmux the restart would be killed with the server it runs in
set +e; out="$(TMUX=/tmp/fake,1,0 "$BIN/tmux-restart" 2>&1)"; rc=$?; set -e
assert_eq "$rc" 64 "restart inside tmux exit"
grep -q 'outside tmux' <<<"$out" || fail "restart inside tmux message: $out"
t has-session -t OPS || fail "refused restart stopped the server"

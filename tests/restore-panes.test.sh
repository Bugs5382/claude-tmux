#!/usr/bin/env bash
set -euo pipefail
. "$ROOT/tests/lib.sh"
mkdir -p "$HOME/bin" "$HOME/Code"
cp "$ROOT/tests/fixtures/fake-claude" "$HOME/bin/claude"
export PATH="$HOME/bin:$PATH" CLAUDE_CALLS="$HOME/calls.txt" CLAUDE_CWDS="$HOME/cwds.txt"
: > "$CLAUDE_CALLS"; : > "$CLAUDE_CWDS"

# A 4-pane window: every pane keeps its own folder and its own Claude session.
for d in d1 d2 d3 d4; do mkdir -p "$HOME/$d"; done
start_server OPS "$HOME/d1"
t split-window -t OPS -c "$HOME/d2"
t split-window -t OPS:0.1 -c "$HOME/d3"
t split-window -t OPS:0.2 -c "$HOME/d4"
t select-layout -t OPS tiled >/dev/null
for p in 0 1 2 3; do t set -p -t "OPS:0.$p" @claude_session "id-$((p + 1))"; done
t select-pane -t OPS:0.2

# An 8-pane window in a second session, then a third session after it.
start_many() { t new-session -d -s "$1" -c "$HOME"; for _ in 1 2 3 4 5 6 7; do t split-window -t "$1" -c "$HOME"; t select-layout -t "$1" tiled >/dev/null; done; }
start_many BIG
t new-session -d -s ZZZ -c "$HOME"
"$BIN/tmux-save" >/dev/null
stop_server

"$BIN/tmux-restore" >/dev/null || fail "restore exit $?"
assert_eq "$(t list-sessions -F '#{session_name}' | sort | paste -sd, -)" "BIG,OPS,ZZZ" "sessions"
assert_eq "$(t list-panes -t OPS:0 -F '#{pane_current_path}' | sed "s#^$HOME/##" | paste -sd, -)" "d1,d2,d3,d4" "pane folders in order"
assert_eq "$(t display -p -t OPS:0 '#{pane_index}')" 2 "active pane"
assert_eq "$(t display -p -t BIG '#{window_panes}')" 8 "8-pane window"
t list-windows -a -F '#{window_index}' | grep -qx 9999 && fail "placeholder window left behind"

for _ in $(seq 1 50); do [ "$(wc -l < "$CLAUDE_CWDS")" -ge 4 ] && break; sleep 0.1; done
assert_eq "$(sed "s#^$HOME/##" "$CLAUDE_CWDS" | sort | paste -sd, -)" "d1 --resume id-1,d2 --resume id-2,d3 --resume id-3,d4 --resume id-4" "each pane resumed its own session"
stop_server

# A session that cannot be rebuilt is reported (exit 3) and the others still come back.
snap="$TMUX_STATE_DIR/snapshots/latest.json"
jq '.sessions |= map(if .name == "BIG" then .windows[0].layout = "garbage" else . end)' "$snap" > "$HOME/broken.json"
set +e; err="$("$BIN/tmux-restore" "$HOME/broken.json" 2>&1 >/dev/null)"; rc=$?; set -e
assert_eq "$rc" 3 "exit when a session fails"
case "$err" in *BIG*) ;; *) fail "failed session not named: $err" ;; esac
t has-session -t =ZZZ 2>/dev/null || fail "sessions after the failed one were not restored"
t has-session -t =OPS 2>/dev/null || fail "sessions before the failed one were lost"

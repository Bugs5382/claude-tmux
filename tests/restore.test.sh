#!/usr/bin/env bash
set -euo pipefail
. "$ROOT/tests/lib.sh"
# Pane IDs (and so the checksum) differ on a new server; compare geometry only.
geometry() { sed -E 's/^[0-9a-f]{4},//; s/([0-9]+x[0-9]+,[0-9]+,[0-9]+),[0-9]+/\1/g'; }
mkdir -p "$HOME/bin" "$HOME/Code" "$HOME/proj a" "$HOME/b"
cp "$ROOT/tests/fixtures/fake-claude" "$HOME/bin/claude"
export PATH="$HOME/bin:$PATH" CLAUDE_CALLS="$HOME/calls.txt"
: > "$CLAUDE_CALLS"

# bad snapshot
set +e; "$BIN/tmux-restore" "$HOME/nope.json" >/dev/null 2>&1; rc=$?; set -e
assert_eq "$rc" 2 "missing snapshot exit"
echo 'not json' > "$HOME/bad.json"
set +e; "$BIN/tmux-restore" "$HOME/bad.json" >/dev/null 2>&1; rc=$?; set -e
assert_eq "$rc" 2 "corrupt snapshot exit"
t has-session 2>/dev/null && fail "server started on a bad snapshot"

# build, save, kill
start_server "OPS" "$HOME/proj a"
t new-session -d -s "PROJECT DESIGN" -c "$HOME/b"
t new-window -t "PROJECT DESIGN" -n "two words" -c "$HOME/proj a"
t split-window -h -t "PROJECT DESIGN:two words" -c "$HOME/b"
t resize-pane -t "PROJECT DESIGN:two words.0" -x 25
t set -p -t "PROJECT DESIGN:two words.1" @claude_session sess-42
mkdir -p "$HOME/gone"; t new-window -t OPS -n tmp -c "$HOME/gone"
"$BIN/tmux-save" >/dev/null
layout_before="$(t display -p -t 'PROJECT DESIGN:two words' '#{window_layout}' | geometry)"
rmdir "$HOME/gone"
stop_server

# --list
"$BIN/tmux-restore" --list | grep -q "OPS" || fail "--list doesn't show sessions"

# restore
"$BIN/tmux-restore" >/dev/null
assert_eq "$(t list-sessions -F '#{session_name}' | sort | paste -sd, -)" "OPS,PROJECT DESIGN" "sessions"
t list-windows -t 'PROJECT DESIGN' -F '#{window_name}' | grep -qx "two words" || fail "spaced window name"
assert_eq "$(t display -p -t 'PROJECT DESIGN:two words' '#{window_panes}')" 2 "pane count"
assert_eq "$(t display -p -t 'PROJECT DESIGN:two words' '#{window_layout}' | geometry)" "$layout_before" "layout"
assert_eq "$(t display -p -t 'OPS:tmp' '#{pane_current_path}')" "$HOME/Code" "missing folder fallback"

# claude resumed only in the tagged pane, and the shell survives its exit
for _ in $(seq 1 50); do [ -s "$CLAUDE_CALLS" ] && break; sleep 0.1; done
assert_eq "$(cat "$CLAUDE_CALLS")" "--resume sess-42" "claude resume args"
sleep 0.3
assert_eq "$(t display -p -t 'PROJECT DESIGN:two words.1' '#{pane_dead}')" 0 "shell alive after claude exits"

# running server: a running session is kept as it is, missing ones are rebuilt, and with no
# terminal nothing attaches
t kill-session -t "=PROJECT DESIGN"
t kill-window -t "=OPS:tmp"
wait_pane_path "$(t split-window -t "=OPS:" -c "$HOME/b" -P -F '#{pane_id}')" "$HOME/b"
ops_before="$(t list-panes -s -t "=OPS" -F '#{window_name} #{pane_current_path}')"
set +e; out="$("$BIN/tmux-restore" 2>&1)"; rc=$?; set -e
assert_eq "$rc" 0 "restore into a running server exit"
printf '%s\n' "$out" | grep -qx "tmux-restore: kept OPS (already running)" || fail "no kept line for OPS: $out"
assert_eq "$(t list-panes -s -t "=OPS" -F '#{window_name} #{pane_current_path}')" "$ops_before" "running OPS untouched"
assert_eq "$(t list-sessions -F '#{session_name}' | sort | paste -sd, -)" "OPS,PROJECT DESIGN" "sessions after restore into a running server"
assert_eq "$(t display -p -t 'PROJECT DESIGN:two words' '#{window_panes}')" 2 "rebuilt pane count"
assert_eq "$(t list-clients | wc -l | tr -d ' ')" 0 "no client attached without a terminal"

# --no-attach on a terminal: restores and returns instead of attaching
with_tty() {
  if script -qec true /dev/null >/dev/null 2>&1; then script -qec "$(printf '%q ' "$@")" /dev/null
  else script -q /dev/null "$@"; fi
}
t kill-session -t "=PROJECT DESIGN"
with_tty "$BIN/tmux-restore" --no-attach > "$HOME/tty.out" 2>&1 < /dev/null &
pid=$!
for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fail "--no-attach did not return"; fi
wait "$pid" || fail "--no-attach exit: $(tr -d '\r' < "$HOME/tty.out")"
assert_eq "$(t list-clients | wc -l | tr -d ' ')" 0 "no client attached with --no-attach"
assert_eq "$(t list-sessions -F '#{session_name}' | sort | paste -sd, -)" "OPS,PROJECT DESIGN" "sessions after --no-attach"
tr -d '\r' < "$HOME/tty.out" | grep -q "^tmux-restore: restored 1 and kept 1 of 2 sessions from " || fail "--no-attach summary: $(cat "$HOME/tty.out")"
tr -d '\r' < "$HOME/tty.out" | grep -q "tmux-restore: kept OPS (already running)$" || fail "--no-attach output: $(cat "$HOME/tty.out")"

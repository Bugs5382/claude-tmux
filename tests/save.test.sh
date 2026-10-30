#!/usr/bin/env bash
set -euo pipefail
. "$ROOT/tests/lib.sh"

# no server: no-op
out="$("$BIN/tmux-save")"; assert_eq "$?" 0 "exit with no server"
case "$out" in *"nothing to save"*) ;; *) fail "no-server message: $out" ;; esac
[ ! -e "$TMUX_STATE_DIR/snapshots/latest.json" ] || fail "wrote a snapshot with no server"

# tmux missing (launchd PATH without Homebrew): fail loudly, not "nothing to save"
mkdir -p "$HOME/emptybin"
set +e; PATH="$HOME/emptybin" /bin/bash "$BIN/tmux-save" >/dev/null 2>&1; rc=$?; set -e
assert_eq "$rc" 127 "exit when tmux is not on PATH"

# shape
mkdir -p "$HOME/a dir" "$HOME/b"
start_server "OPS" "$HOME/a dir"
t new-window -t OPS -n work -c "$HOME/b"
t split-window -t OPS:work -c "$HOME/a dir"
t set -p -t OPS:work.1 @claude_session abc-123
"$BIN/tmux-save"
snap="$TMUX_STATE_DIR/snapshots/latest.json"
jq -e . "$snap" >/dev/null || fail "latest.json is not valid JSON"
assert_eq "$(jq -r '.sessions[0].name' "$snap")" "OPS" "session name"
assert_eq "$(jq -r '.sessions[0].windows | length' "$snap")" "2" "window count"
assert_eq "$(jq -r '.sessions[0].windows[1].name' "$snap")" "work" "window name"
assert_eq "$(jq -r '.sessions[0].windows[1].panes | length' "$snap")" "2" "pane count"
assert_eq "$(jq -r '.sessions[0].windows[0].panes[0].cwd' "$snap")" "$HOME/a dir" "cwd with space"
assert_eq "$(jq -r '[.sessions[0].windows[1].panes[].claude_session] | map(select(.!=null)) | .[0]' "$snap")" "abc-123" "claude tag"
assert_eq "$(jq -r '.sessions[0].windows[0].panes[0].claude_session' "$snap")" "null" "untagged pane"

# atomic write: no temp files left, latest is a symlink
[ -L "$snap" ] || fail "latest.json is not a symlink"
[ -z "$(find "$TMUX_STATE_DIR/snapshots" -name '*.tmp*')" ] || fail "temp file left behind"

# prune to keep
for i in $(seq -w 1 30); do echo '{}' > "$TMUX_STATE_DIR/snapshots/20200101T0000${i}Z.json"; done
"$BIN/tmux-save"
assert_eq "$(find "$TMUX_STATE_DIR/snapshots" -name '*Z.json' | wc -l | tr -d ' ')" "24" "pruned to 24"
jq -e '.sessions' "$TMUX_STATE_DIR/snapshots/latest.json" >/dev/null || fail "newest snapshot was pruned"

# launchd starts tmux-save with no locale; tmux then escapes tabs and UTF-8 in its output
t rename-session -t OPS "OPS café"
env -u LANG -u LC_ALL -u LC_CTYPE "$BIN/tmux-save" >/dev/null
assert_eq "$(jq -r '.sessions[0].name' "$TMUX_STATE_DIR/snapshots/latest.json")" "OPS café" "save with no locale"

# another save holding the lock: leave a pending mark for it and exit 0
mkdir "$TMUX_STATE_DIR/save.lock"; echo "$$" > "$TMUX_STATE_DIR/save.lock/pid"
out="$("$BIN/tmux-save")"
case "$out" in *"another save is running"*) ;; *) fail "held lock: $out" ;; esac
[ -e "$TMUX_STATE_DIR/save.pending" ] || fail "no pending mark for the running save"
[ -d "$TMUX_STATE_DIR/save.lock" ] || fail "removed another save's lock"

# a lock left by a dead save is cleared, and the pending mark is picked up
sh -c 'exit 0' & dead=$!; wait "$dead"
echo "$dead" > "$TMUX_STATE_DIR/save.lock/pid"
"$BIN/tmux-save" >/dev/null
[ ! -e "$TMUX_STATE_DIR/save.lock" ] || fail "stale lock left behind"
[ ! -e "$TMUX_STATE_DIR/save.pending" ] || fail "pending mark left behind"

# saves started together all succeed and leave a valid latest.json
pids=()
for _ in 1 2 3 4 5; do "$BIN/tmux-save" >/dev/null & pids+=("$!"); done
for p in "${pids[@]}"; do wait "$p" || fail "a parallel save failed"; done
jq -e '.sessions[0].name' "$TMUX_STATE_DIR/snapshots/latest.json" >/dev/null || fail "latest.json invalid after parallel saves"
[ ! -e "$TMUX_STATE_DIR/save.lock" ] || fail "lock left after parallel saves"

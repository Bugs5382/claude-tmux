#!/usr/bin/env bash
set -euo pipefail
. "$ROOT/tests/lib.sh"
hook="$ROOT/hooks/tmux-claude-tag.sh"

# outside tmux: silent, exit 0
out="$("$hook" < "$FIXTURES/session-start.json")"; assert_eq "$out" "" "no output outside tmux"

start_server OPS
pane="$(t display -p -t OPS '#{pane_id}')"
sockpath="$(t display -p '#{socket_path}')"
export TMUX="$sockpath,0,0" TMUX_PANE="$pane"

out="$("$hook" < "$FIXTURES/session-start.json")"
assert_eq "$out" "" "no stdout on SessionStart"
assert_eq "$(t show -pv -t "$pane" @claude_session)" "sess-77" "tagged"

"$hook" < "$FIXTURES/session-end.json"
assert_eq "$(t show -pv -t "$pane" @claude_session 2>/dev/null || true)" "" "untagged"

echo '{garbage' | "$hook"; assert_eq "$?" 0 "bad input still exits 0"

# SessionEnd for another session (a nested `claude -p`) leaves this pane's tag alone
"$hook" < "$FIXTURES/session-start.json"
jq '.session_id = "other-1"' "$FIXTURES/session-end.json" | "$hook"
assert_eq "$(t show -pv -t "$pane" @claude_session)" "sess-77" "other session's end keeps the tag"

# Only the pane's own Claude (the pane process or a child of its shell) may tag it
pane_pid="$(t display -p -t "$pane" '#{pane_pid}')"
t send-keys -t "$pane" 'sleep 300' Enter
child=""
for _ in $(seq 1 50); do child="$(pgrep -P "$pane_pid" sleep || true)"; [ -n "$child" ] && break; sleep 0.1; done
[ -n "$child" ] || fail "no child process in the pane"
jq '.session_id = "nested-1"' "$FIXTURES/session-start.json" | CLAUDE_PID=$$ "$hook"
assert_eq "$(t show -pv -t "$pane" @claude_session)" "sess-77" "nested claude does not retag"
jq '.session_id = "nested-1"' "$FIXTURES/session-end.json" | CLAUDE_PID=$$ "$hook"
assert_eq "$(t show -pv -t "$pane" @claude_session)" "sess-77" "nested claude does not untag"
jq '.session_id = "own-1" | .source = "clear"' "$FIXTURES/session-start.json" | CLAUDE_PID="$child" "$hook"
assert_eq "$(t show -pv -t "$pane" @claude_session)" "own-1" "pane's own claude retags (after /clear)"
jq '.session_id = "own-2"' "$FIXTURES/session-start.json" | CLAUDE_PID="$pane_pid" "$hook"
assert_eq "$(t show -pv -t "$pane" @claude_session)" "own-2" "claude as the pane process tags"
t send-keys -t "$pane" C-c

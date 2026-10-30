#!/usr/bin/env bash
# Claude SessionStart/SessionEnd hook: tag the tmux pane with the Claude session ID so tmux-restore can resume it.
# No -e: a hook must never block Claude, so it always exits 0.
set -uo pipefail
input="$(cat)"
[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0
event="$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null)"
id="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)"

# A nested `claude -p` (run from a script or a tool) inherits TMUX_PANE; only the pane's own
# Claude, the pane process or a child of the pane's shell, owns the tag.
if [ -n "${CLAUDE_PID:-}" ]; then
  pane_pid="$(tmux display -p -t "$TMUX_PANE" '#{pane_pid}' 2>/dev/null)"
  if [ -n "$pane_pid" ] && [ "$CLAUDE_PID" != "$pane_pid" ] \
    && [ "$(ps -o ppid= -p "$CLAUDE_PID" 2>/dev/null | tr -d ' ')" != "$pane_pid" ]; then
    exit 0
  fi
fi

case "$event" in
  SessionStart) [ -n "$id" ] && tmux set -p -t "$TMUX_PANE" @claude_session "$id" >/dev/null 2>&1 ;;
  SessionEnd)
    if [ "$(tmux show -pv -t "$TMUX_PANE" @claude_session 2>/dev/null)" = "$id" ]; then
      tmux set -pu -t "$TMUX_PANE" @claude_session >/dev/null 2>&1
    fi ;;
esac
exit 0

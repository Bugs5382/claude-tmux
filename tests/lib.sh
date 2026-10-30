#!/usr/bin/env bash
# Shared helpers: a private tmux server per test file, never the real one.
set -euo pipefail
# macOS temp dirs sit behind the /var -> /private/var symlink; tmux reports real paths.
HOME="$(cd "$HOME" && pwd -P)"
export HOME
export TMUX_SOCKET_NAME="claude-tmux-test-$$"
export TMUX_STATE_DIR="$HOME/state"
export TMUX_CONFIG=/dev/null
# tmux-start checks for a release in the background; a test never reaches GitHub.
export CLAUDE_TMUX_RELEASE_URL=file:///nonexistent
# tmux leaves its socket file behind after kill-server; keep them out of /tmp/tmux-<uid>.
TMUX_TMPDIR="$(mktemp -d /tmp/claude-tmux-test.XXXXXX)"
export TMUX_TMPDIR
unset TMUX TMUX_PANE CLAUDE_PID
export BIN="$ROOT/bin"

t() { tmux -L "$TMUX_SOCKET_NAME" -f /dev/null "$@"; }
start_server() { t new-session -d -s "$1" -c "${2:-$HOME}"; }
stop_server() { t kill-server 2>/dev/null || true; }
trap 'stop_server; rm -rf "$TMUX_TMPDIR"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3: expected [$2] got [$1]"; }
# On Linux a new pane reports an empty path until its process has started.
wait_pane_path() {
  local i
  for (( i = 0; i < 50; i++ )); do
    [ "$(t display -p -t "$1" '#{pane_current_path}')" = "$2" ] && return 0
    sleep 0.1
  done
  fail "pane $1 never reached $2"
}

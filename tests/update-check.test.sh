#!/usr/bin/env bash
set -euo pipefail
. "$ROOT/tests/lib.sh"

mkdir -p "$HOME/bin" "$HOME/.local/bin"
cp "$FIXTURES/fake-git" "$HOME/bin/git"
cp "$FIXTURES/fake-claude" "$HOME/bin/claude"
export PATH="$HOME/bin:$PATH" GIT_CALLS="$HOME/git-calls.txt" CLAUDE_CALLS="$HOME/calls.txt"
log="$TMUX_STATE_DIR/update-check.log"
release="$HOME/release.json"
check="$ROOT/lib/update-check.sh"

wait_for() { for (( i = 0; i < 80; i++ )); do [ -s "$1" ] && grep -q "$2" "$1" && return 0; sleep 0.1; done; return 1; }
publish() { printf '{"tag_name": "%s"}\n' "$1" > "$release"; export CLAUDE_TMUX_RELEASE_URL="file://$release"; }
outcome() { rm -f "$log"; "$check"; tail -1 "$log"; }

# Compare without a client: nothing newer means no wait and one line in the log.
export FAKE_GIT_TAG=v1.2.0
publish v1.2.0;  grep -q 'up to date'   <<<"$(outcome)" || fail "same version"
publish v1.1.9;  grep -q 'up to date'   <<<"$(outcome)" || fail "older release"
publish v1.10.0; rm -f "$log"
start_server OPS
script_client() {
  if [ "$(uname -s)" = Darwin ]; then
    TERM=xterm script -q /dev/null tmux -L "$TMUX_SOCKET_NAME" -f /dev/null attach -t "=OPS"
  else
    TERM=xterm script -qc "tmux -L $TMUX_SOCKET_NAME -f /dev/null attach -t =OPS" /dev/null
  fi
}
# Open stdin: at end of file script sends ^D to the pane, whose shell exit ends the server.
sleep 15 | script_client >/dev/null 2>&1 &
"$check"
grep -q 'newer: v1.10.0' "$log" || fail "numeric compare: $(cat "$log")"
t show-messages | grep -q 'claude-tmux v1.10.0 is out' || fail "no message: $(t show-messages)"
stop_server

# A release that can't be read, a tag with tmux formats in it, a checkout with no tag: all quiet.
export CLAUDE_TMUX_RELEASE_URL=file:///nonexistent
grep -q 'no release' <<<"$(outcome)" || fail "unreachable"
# shellcheck disable=SC2016 # the format must reach the check unexpanded
publish '#(touch $HOME/pwned)'
grep -q 'no release' <<<"$(outcome)" || fail "unsafe tag"
[ ! -e "$HOME/pwned" ] || fail "tag was expanded"
publish v9.0.0; unset FAKE_GIT_TAG
grep -q 'no installed tag' <<<"$(outcome)" || fail "no tag"

# Linked onto PATH, tmux-start still finds its checkout, and the check runs once.
ln -s "$BIN/tmux-start" "$HOME/.local/bin/tmux-start"
rm -f "$log" "$GIT_CALLS"
export FAKE_GIT_TAG=v9.0.0
"$HOME/.local/bin/tmux-start" </dev/null >/dev/null
wait_for "$log" 'up to date' || fail "tmux-start ran no check"
grep -q -- "-C $ROOT " "$GIT_CALLS" || fail "wrong checkout: $(cat "$GIT_CALLS")"
assert_eq "$(wc -l < "$log" | tr -d ' ')" 1 "one check"
stop_server

# A network that hangs doesn't hold tmux-start up.
cp "$FIXTURES/fake-curl-hang" "$HOME/bin/curl"
rm -f "$log"
begin=$SECONDS
"$BIN/tmux-start" </dev/null >/dev/null
[ $(( SECONDS - begin )) -lt 2 ] || fail "tmux-start waited on the network"
wait_for "$log" 'no release' || fail "hung check: $(cat "$log")"
rm "$HOME/bin/curl"
stop_server

# Nothing else checks.
rm -f "$log"
start_server OPS
"$BIN/tmux-save" >/dev/null
"$BIN/tmux-stop" >/dev/null
for (( i = 0; i < 50; i++ )); do t has-session 2>/dev/null || break; sleep 0.1; done
"$BIN/tmux-restore" --no-attach >/dev/null
sleep 0.5
[ ! -e "$log" ] || fail "something other than tmux-start checked: $(cat "$log")"

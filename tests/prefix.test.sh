#!/usr/bin/env bash
set -euo pipefail
. "$ROOT/tests/lib.sh"

prefix() { t show -gv prefix; }
sends() { t list-keys -T prefix | grep -q "$1 *send-prefix"; }
unset SSH_CONNECTION SSH_TTY

# no server is an error, not a server started by accident
set +e; "$BIN/tmux-prefix" ssh >/dev/null 2>&1; rc=$?; set -e
assert_eq "$rc" 1 "prefix with no server"

start_server OPS
"$BIN/tmux-prefix" ssh >/dev/null
assert_eq "$(prefix)" C-a "ssh prefix"
sends C-a || fail "C-a C-a does not send a real C-a"
"$BIN/tmux-prefix" local >/dev/null
assert_eq "$(prefix)" C-b "local prefix"
sends C-b || fail "C-b C-b does not send a real C-b"
if sends C-a; then fail "C-a still bound on a local prefix"; fi

# the question: an answer wins, Enter takes what the connection says
echo y | "$BIN/tmux-prefix" >/dev/null
assert_eq "$(prefix)" C-a "answered y"
echo n | SSH_CONNECTION="192.0.2.1 1 192.0.2.2 22" "$BIN/tmux-prefix" >/dev/null
assert_eq "$(prefix)" C-b "answered n on ssh"
echo | SSH_CONNECTION="192.0.2.1 1 192.0.2.2 22" "$BIN/tmux-prefix" >/dev/null
assert_eq "$(prefix)" C-a "enter on ssh"
echo | "$BIN/tmux-prefix" >/dev/null
assert_eq "$(prefix)" C-b "enter on local"
"$BIN/tmux-prefix" </dev/null >/dev/null
assert_eq "$(prefix)" C-b "no answer on local"

set +e; "$BIN/tmux-prefix" nope >/dev/null 2>&1; rc=$?; set -e
assert_eq "$rc" 64 "bad argument"

# tmux-start makes OPS when it is missing and leaves it alone when it is not
stop_server
out="$("$BIN/tmux-start" </dev/null)"
t has-session -t "=OPS" || fail "tmux-start did not create OPS"
grep -q 'tmux attach' <<<"$out" || fail "tmux-start with no terminal: $out"
t new-window -d -t OPS -n keep
"$BIN/tmux-start" </dev/null >/dev/null
t list-windows -t OPS -F '#{window_name}' | grep -qx keep || fail "tmux-start replaced OPS"

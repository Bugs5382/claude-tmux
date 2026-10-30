#!/usr/bin/env bash
set -euo pipefail
. "$ROOT/tests/lib.sh"

# pbcopy picks the macOS bindings; a stand-in keeps that path testable on Linux CI.
mkdir -p "$HOME/fakebin"
printf '#!/bin/sh\ncat >/dev/null\n' > "$HOME/fakebin/pbcopy"; chmod +x "$HOME/fakebin/pbcopy"
PATH="$HOME/fakebin:$PATH" start_server OPS
t source-file "$ROOT/tmux.conf" || fail "tmux.conf has errors"
assert_eq "$(t show -gv mouse)" "on" "mouse"
assert_eq "$(t show -gv base-index)" "1" "base-index"
assert_eq "$(t show -gwv pane-base-index)" "1" "pane-base-index"
assert_eq "$(t show -gv history-limit)" "50000" "history-limit"
t list-keys -T copy-mode | grep -Eq 'MouseDragEnd1Pane +send-keys -X copy-pipe-and-cancel pbcopy' || fail "drag does not copy to the clipboard"

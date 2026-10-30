#!/usr/bin/env bash
set -euo pipefail
. "$ROOT/tests/lib.sh"
# Without pbcopy, tmux.conf copies with wl-copy on Wayland, xclip on X11, or OSC 52 (set-clipboard
# on) when neither is there, as over SSH. tmux decides when it loads the config, from the server's
# environment, so each case starts its own server with only the PATH and display it names.
mkdir -p "$HOME/none" "$HOME/wl" "$HOME/x"
for b in wl-copy:wl xclip:x; do
  printf '#!/bin/sh\ncat >/dev/null\n' > "$HOME/${b#*:}/${b%%:*}"; chmod +x "$HOME/${b#*:}/${b%%:*}"
done
sys="$(dirname "$(command -v tmux)"):$(dirname "$(command -v sh)")"

case_conf() { # <name> <PATH prefix> <env...>
  local name="$1" pre="$2"; shift 2
  stop_server
  # A fresh socket per case: kill-server returns before the old server is gone, and a new
  # session on the same socket can reach the dying server ("server exited unexpectedly").
  TMUX_SOCKET_NAME="claude-tmux-test-$$-$name"
  env -i HOME="$HOME" TMUX_TMPDIR="$TMUX_TMPDIR" PATH="$pre:$sys" "$@" \
    tmux -L "$TMUX_SOCKET_NAME" -f /dev/null new-session -d -s OPS
  t source-file "$ROOT/tmux.conf" || fail "$name: tmux.conf has errors"
  keys="$(t list-keys -T copy-mode; t list-keys -T copy-mode-vi)"
  ! grep -q pbcopy <<<"$keys" || fail "$name: bound pbcopy without pbcopy"
}

case_conf wayland "$HOME/wl" WAYLAND_DISPLAY=wayland-0
grep -Eq 'MouseDragEnd1Pane +send-keys -X copy-pipe-and-cancel wl-copy' <<<"$keys" || fail "wayland drag: $keys"
grep -Eq 'copy-mode +y +send-keys -X copy-pipe-and-cancel wl-copy' <<<"$keys" || fail "wayland y"

case_conf x11 "$HOME/x" DISPLAY=:0
grep -Eq 'MouseDragEnd1Pane +send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in"' <<<"$keys" || fail "x11 drag: $keys"

# wl-copy installed but no Wayland session (an X11 desktop with both): xclip, not wl-copy.
case_conf x11-with-wl "$HOME/wl:$HOME/x" DISPLAY=:0
grep -q 'xclip' <<<"$keys" || fail "x11 with wl-copy installed: $keys"
! grep -q 'wl-copy' <<<"$keys" || fail "x11 with wl-copy installed bound wl-copy"

case_conf ssh "$HOME/none"
grep -Eq 'MouseDragEnd1Pane +send-keys -X copy-selection-and-cancel' <<<"$keys" || fail "ssh drag: $keys"
grep -Eq 'copy-mode-vi +y +send-keys -X copy-selection-and-cancel' <<<"$keys" || fail "ssh y"
assert_eq "$(t show -sv set-clipboard)" "on" "OSC 52 clipboard over SSH"

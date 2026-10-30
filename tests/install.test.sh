#!/usr/bin/env bash
set -euo pipefail
# install.sh writes into $HOME: only ever run it in the temporary HOME from tests/run.sh.
case "$(basename "$HOME")" in test-home.*) ;; *) echo "FAIL: HOME is not a test home: $HOME" >&2; exit 1 ;; esac
# The macOS path, whatever OS runs the tests.
export CLAUDE_TMUX_OS=Darwin
export CLAUDE_TMUX_NO_LAUNCHCTL=1
printf 'my own config\n' > "$HOME/.tmux.conf"
out="$(bash "$ROOT/install.sh")"
for l in .tmux.conf .local/bin/tmux-save .local/bin/tmux-restore .local/bin/tmux-stop .local/bin/tmux-restart .claude/hooks/tmux-claude-tag.sh; do
  [ -L "$HOME/$l" ] || { echo "FAIL: $l not linked" >&2; exit 1; }
done
# an existing real file is moved aside, never overwritten
bak="$(find "$HOME" -maxdepth 1 -name '.tmux.conf.bak.*' | head -1)"
[ -n "$bak" ] && [ "$(cat "$bak")" = "my own config" ] || { echo "FAIL: existing ~/.tmux.conf not backed up" >&2; exit 1; }
plist="$HOME/Library/LaunchAgents/com.bugs5382.tmux-save.plist"
[ -f "$plist" ] && [ ! -L "$plist" ] || { echo "FAIL: plist not copied" >&2; exit 1; }
grep -q "$HOME/.local/bin/tmux-save" "$plist" || { echo "FAIL: plist path" >&2; exit 1; }
grep -q "/opt/homebrew/bin" "$plist" || { echo "FAIL: plist PATH" >&2; exit 1; }
grep -q '<integer>3600</integer>' "$plist" || { echo "FAIL: interval" >&2; exit 1; }
# plutil is macOS only; CI runs on Linux, where Python's plistlib parses the same format.
if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$plist" >/dev/null || { echo "FAIL: plist invalid" >&2; exit 1; }
else
  python3 -c 'import plistlib, sys; plistlib.load(open(sys.argv[1], "rb"))' "$plist" || { echo "FAIL: plist invalid" >&2; exit 1; }
fi
{ grep -q '"SessionStart"' <<<"$out" && grep -q '"SessionEnd"' <<<"$out"; } || { echo "FAIL: snippet" >&2; exit 1; }
bash "$ROOT/install.sh" >/dev/null   # idempotent

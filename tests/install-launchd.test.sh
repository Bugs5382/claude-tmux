#!/usr/bin/env bash
set -euo pipefail
# install.sh writes into $HOME: only ever run it in the temporary HOME from tests/run.sh.
case "$(basename "$HOME")" in test-home.*) ;; *) echo "FAIL: HOME is not a test home: $HOME" >&2; exit 1 ;; esac
# The macOS path, whatever OS runs the tests.
export CLAUDE_TMUX_OS=Darwin
unset CLAUDE_TMUX_NO_LAUNCHCTL
mkdir -p "$HOME/bin"
cp "$ROOT/tests/fixtures/fake-launchctl" "$HOME/bin/launchctl"
export PATH="$HOME/bin:$PATH" LAUNCHCTL_STATE="$HOME/launchctl.state"
# Never let the real launchctl run from a test.
[ "$(command -v launchctl)" = "$HOME/bin/launchctl" ] || { echo "FAIL: fake launchctl not first on PATH" >&2; exit 1; }

echo 1 > "$LAUNCHCTL_STATE"   # a re-install: the agent is already loaded
bash "$ROOT/install.sh" >/dev/null || { echo "FAIL: re-install exit $?" >&2; exit 1; }
[ "$(cat "$LAUNCHCTL_STATE")" = 1 ] || { echo "FAIL: agent not loaded again" >&2; exit 1; }

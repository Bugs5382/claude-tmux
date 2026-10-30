#!/usr/bin/env bash
# Link claude-tmux into place and start the hourly save: a launchd agent on macOS, a systemd user
# timer on Linux. Safe to run again.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
label=com.bugs5382.tmux-save
os="${CLAUDE_TMUX_OS:-$(uname -s)}"

case "$os" in
  Darwin|Linux) ;;
  *) echo "install.sh: $os is not supported (macOS and Linux only); nothing changed" >&2; exit 1 ;;
esac

link() {
  mkdir -p "$(dirname "$2")"
  if [ -e "$2" ] && [ ! -L "$2" ]; then
    local bak
    bak="$2.bak.$(date +%Y%m%d%H%M%S)"
    mv "$2" "$bak"
    echo "moved your existing $2 to $bak"
  fi
  ln -sfn "$1" "$2"
  echo "linked $2"
}
link "$ROOT/tmux.conf" "$HOME/.tmux.conf"
link "$ROOT/bin/tmux-save" "$HOME/.local/bin/tmux-save"
link "$ROOT/bin/tmux-restore" "$HOME/.local/bin/tmux-restore"
link "$ROOT/bin/tmux-stop" "$HOME/.local/bin/tmux-stop"
link "$ROOT/bin/tmux-restart" "$HOME/.local/bin/tmux-restart"
link "$ROOT/hooks/tmux-claude-tag.sh" "$HOME/.claude/hooks/tmux-claude-tag.sh"

install_launchd() {
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/state/tmux"
  plist="$HOME/Library/LaunchAgents/$label.plist"
  sed "s#__HOME__#$HOME#g" "$ROOT/launchd/$label.plist" > "$plist"
  echo "wrote $plist"
  if [ -z "${CLAUDE_TMUX_NO_LAUNCHCTL:-}" ]; then
    domain="gui/$(id -u)"
    if launchctl print "$domain/$label" >/dev/null 2>&1; then
      launchctl bootout "$domain/$label" 2>/dev/null || true
      # bootout returns before the agent is gone, and bootstrap fails (error 5) until it is.
      for _ in $(seq 1 50); do launchctl print "$domain/$label" >/dev/null 2>&1 || break; sleep 0.1; done
    fi
    launchctl bootstrap "$domain" "$plist"
    echo "loaded $label (every hour)"
  fi
}

install_systemd() {
  local units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" u
  mkdir -p "$units" "$HOME/.local/state/tmux"
  for u in tmux-save.service tmux-save.timer; do
    cp "$ROOT/systemd/$u" "$units/$u"
    echo "wrote $units/$u"
  done
  [ -z "${CLAUDE_TMUX_NO_SYSTEMCTL:-}" ] || return 0
  # A container, or a box with no login session, has no user manager to talk to.
  if ! systemctl --user daemon-reload 2>/dev/null; then
    echo "note: no systemd user manager is running here, so the hourly save is not on yet."
    echo "  Once you are in a normal login session, run: systemctl --user enable --now tmux-save.timer"
    return 0
  fi
  systemctl --user enable --now tmux-save.timer
  echo "enabled tmux-save.timer (every hour)"
}

if [ "$os" = Darwin ]; then install_launchd; else install_systemd; fi

# shellcheck disable=SC2088 # printed for the reader, not expanded
rc="~/.zshrc"
# shellcheck disable=SC2088
[ "$os" = Darwin ] || rc="~/.$(basename "${SHELL:-bash}")rc"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "note: add this to $rc so the tmux commands are on PATH:"
     echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

cat <<EOT

Add these to the "hooks" block in ~/.claude/settings.json (next to the existing entries):
  "SessionStart": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/tmux-claude-tag.sh"}]}],
  "SessionEnd":   [{"hooks": [{"type": "command", "command": "~/.claude/hooks/tmux-claude-tag.sh"}]}]
If SessionStart already has entries, add the command to its list instead of a second key.
EOT

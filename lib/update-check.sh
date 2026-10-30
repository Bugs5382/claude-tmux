#!/usr/bin/env bash
# Run in the background by tmux-start: if GitHub has a newer release than this checkout's tag, say
# so in the tmux client. Installs nothing. Every failure is quiet and only reaches the log.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sock="${TMUX_SOCKET_NAME:-default}"
state="${TMUX_STATE_DIR:-$HOME/.local/state/tmux}"
url="${CLAUDE_TMUX_RELEASE_URL:-https://api.github.com/repos/Bugs5382/claude-tmux/releases/latest}"

log() { mkdir -p "$state" && printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$state/update-check.log"; }

installed="$(git -C "$root" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null)" || {
  log "no installed tag in $root"
  exit 0
}

# /releases/latest skips drafts and prereleases, and is a 404 until something is published.
latest="$(curl -fsSL --connect-timeout 2 --max-time 4 "$url" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null)" || latest=""

# display-message expands tmux formats, so nothing but a plain version gets near it.
if [[ ! "$latest" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  log "no release to compare against $installed"
  exit 0
fi

if [ "$latest" = "$installed" ] || [ "$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -1)" != "$latest" ]; then
  log "up to date: $installed, latest $latest"
  exit 0
fi

log "newer: $latest, installed $installed"
# The prefix question comes before the attach, so wait for a client to show the message to.
for (( i = 0; i < 120; i++ )); do
  client="$(tmux -L "$sock" list-clients -t "=OPS" -F '#{client_name}' 2>/dev/null | head -1)"
  if [ -n "$client" ]; then
    tmux -L "$sock" display-message -c "$client" -d 15000 \
      "claude-tmux $latest is out (you have $installed). To update, run git pull in your clone."
    exit 0
  fi
  sleep 0.5
done
log "no client attached, message not shown"

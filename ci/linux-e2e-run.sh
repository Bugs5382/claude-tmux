#!/usr/bin/env bash
# Builds the systemd Ubuntu image, boots it, and runs ci/linux-e2e.sh in it as a normal user.
# Used by CI and locally (needs docker). Removes its container when done.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="claude-tmux-e2e-$$"
docker build -q -t claude-tmux-e2e -f "$ROOT/ci/linux.Dockerfile" "$ROOT/ci" >/dev/null
docker run -d --name "$name" --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v "$ROOT:/src:ro" claude-tmux-e2e >/dev/null
trap 'docker rm -f "$name" >/dev/null' EXIT
# Wait for boot to finish (degraded is fine: some units can't start in a container).
for _ in $(seq 1 60); do
  s="$(docker exec "$name" systemctl is-system-running 2>/dev/null || true)"
  case "$s" in running|degraded) break ;; esac
  sleep 1
done
uid="$(docker exec "$name" id -u tester)"
for _ in $(seq 1 30); do
  docker exec "$name" test -S "/run/user/$uid/bus" && break
  sleep 1
done
docker exec -u tester -w /home/tester -e HOME=/home/tester -e "XDG_RUNTIME_DIR=/run/user/$uid" \
  "$name" bash /src/ci/linux-e2e.sh

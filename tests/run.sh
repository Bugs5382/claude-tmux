#!/usr/bin/env bash
# Run every tests/*.test.sh in its own bash process and fail if any fails.
#
# Each test gets a fresh temporary HOME and no CLAUDE_CONFIG_DIR, so nothing a
# test does can reach the real ~/.claude. Tests find the repo in $ROOT and the
# sample payloads in $FIXTURES.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures"
export ROOT FIXTURES
unset CLAUDE_CONFIG_DIR

total=0
failed=0
for t in "$ROOT"/tests/*.test.sh; do
  [ -e "$t" ] || continue
  total=$((total + 1))
  home="$(mktemp -d "${TMPDIR:-/tmp}/test-home.XXXXXX")"
  if HOME="$home" bash "$t"; then
    printf 'ok   %s\n' "$(basename "$t")"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$(basename "$t")"
  fi
  rm -rf "$home"
done

printf '%d tests, %d failed\n' "$total" "$failed"
[ "$failed" -eq 0 ]

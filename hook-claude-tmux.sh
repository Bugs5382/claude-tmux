#!/usr/bin/env bash
# tmux sessions for Claude on macOS and Linux: hourly snapshots and a restore that resumes each conversation.
#
# Claude runs this with a JSON payload on stdin. Whatever goes wrong, it
# must not break the session: print what it can and exit 0. No -e for that
# reason, so one failed command never ends the script early.
set -uo pipefail

# Read the payload up front so Claude is never left writing to a pipe
# nobody drains.
# shellcheck disable=SC2034
payload="$(cat)"

exit 0

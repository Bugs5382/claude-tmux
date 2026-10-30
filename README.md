# claude-tmux 🪝

> 🧭 tmux sessions for Claude on macOS and Linux: hourly snapshots and a restore that resumes each conversation.

## 📦 Install

Needs bash and `jq`; runs on macOS and Linux.

```bash
bash install.sh
```

`install.sh` copies `hook-claude-tmux.sh` into `~/.claude/hooks/` (or `$CLAUDE_CONFIG_DIR/hooks/`)
and prints the snippet to add to `settings.json`. It never edits `settings.json` itself.

## 🛠 Develop

```bash
task lint    # shellcheck over every script
task test    # tests/run.sh: every tests/*.test.sh, each in a temporary HOME
```

## ⚖️ License

MIT (c) 2026 Shane

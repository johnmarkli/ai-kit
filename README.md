# ai-kit

Minimal, repo-agnostic setup for reusable AI coding-agent context.

## Structure

- `agents/AGENTS.core.md` - core instructions shared across agents
- `skills/investigate-bug/SKILL.md` - reusable debugging workflow
- `skills/code-review/SKILL.md` - reusable pull request/code review workflow
- `scripts/run-agent.sh` - ad hoc context composer + launcher

## What `run-agent.sh` does

1. Builds a temporary runtime context file from:
   - `agents/AGENTS.core.md`
   - optional `--task` text
2. Launches the selected agent with that context appended as system prompt (`--append-system-prompt`)
3. For `pi`, relies on native skills discovery from `~/.pi/agent/skills`
4. For `claude`, relies on native skills discovery from `~/.claude/skills`
5. Warns if either skills symlink is missing/misconfigured
6. Cleans up the temp file automatically

This keeps instructions out of target repos and injects context only at runtime.

## Usage

```bash
chmod +x scripts/run-agent.sh
```

### Pi

```bash
./scripts/run-agent.sh --agent pi --task "debug failing tests" -- "help me fix this"
```

### Claude

```bash
./scripts/run-agent.sh --agent claude --task "review auth flow" -- "find root cause"
```

### Dry run (no launch)

```bash
./scripts/run-agent.sh --agent pi --task "debug failing tests" --dry-run -- "help me fix this"
```

Shows:
- resolved skills symlink paths
- exact command that would run
- composed runtime context

### Pass-through flags to underlying agent

Use a second `--` to pass flags directly to `pi` or `claude`:

```bash
./scripts/run-agent.sh --agent pi -- "help me fix this" -- --model openai/gpt-4o --print
./scripts/run-agent.sh --agent claude -- "review this diff" -- --model sonnet --print
```

Precedence note:
- The wrapper always injects `--append-system-prompt` with composed context.
- Your pass-through flags are appended after that.
- If you pass conflicting flags, the underlying CLI's own argument resolution rules apply.

## Skills symlink setup (shared source of truth)

Point both tools to this repo's `skills/`:

```bash
mkdir -p ~/.pi/agent ~/.claude
ln -sfn "$(pwd)/skills" ~/.pi/agent/skills
ln -sfn "$(pwd)/skills" ~/.claude/skills
```

If you use a custom Pi agent dir, set `PI_CODING_AGENT_DIR` and symlink there instead.

## Notes

- Both `pi` and `claude` use native skills discovery via symlinked skills directories.
- Add more skills under `skills/<skill-name>/SKILL.md`.

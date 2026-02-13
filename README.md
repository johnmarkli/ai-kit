# ai-kit

Minimal, repo-agnostic setup for reusable AI coding-agent context.

## Structure

- `agents/AGENTS.core.md` - core instructions shared across agents
- `agents/AGENTS.tools.md` - tool usage defaults
- `agents/AGENTS.lang.go.md` - Go-specific conventions
- `agents/AGENTS.lang.ts.md` - TypeScript-specific conventions
- `agents/profiles.yaml` - profile-based context composition
- `skills/` - reusable skill packs (`skills/<skill-name>/SKILL.md`)
- `scripts/run-agent.sh` - profile-aware context composer + launcher

## What `run-agent.sh` does

1. Resolves a profile from `agents/profiles.yaml` (default: `default`)
2. Builds a temporary runtime context file by concatenating profile files
3. Launches the selected agent with that context appended as system prompt (`--append-system-prompt`)
4. For `pi`, relies on native skills discovery from `~/.pi/agent/skills`
5. For `claude`, relies on native skills discovery from `~/.claude/skills`
6. Warns if either skills symlink is missing/misconfigured
7. Cleans up the temp file automatically

This keeps instructions out of target repos and injects context only at runtime.

## Usage

```bash
chmod +x scripts/run-agent.sh
```

Requirements:
- `bash` 4+
- `yq` v4 (used for parsing `agents/profiles.yaml`)

### Pi

```bash
./scripts/run-agent.sh --agent pi -- "help me fix this"
```

### Claude

```bash
./scripts/run-agent.sh --agent claude -- "find root cause"
```

### Select a profile

```bash
./scripts/run-agent.sh --agent pi --profile go -- "fix failing go tests"
```

### List profiles

```bash
./scripts/run-agent.sh --agent pi --list-profiles
```

### Profile inheritance (`extends`)

Profiles can inherit other profiles and append files in order.

```yaml
profiles:
  default:
    files:
      - agents/AGENTS.core.md
      - agents/AGENTS.tools.md

  ph:
    extends: default
    files:
      - agents/AGENTS.org.ph.md

  ph-ts:
    extends: ph
    files:
      - agents/AGENTS.lang.ts.md
```

In this example, `ph-ts` resolves to: core + tools + org + typescript.

### Dry run (no launch)

```bash
./scripts/run-agent.sh --agent pi --profile go --dry-run -- "help me fix this"
```

Shows:
- resolved context files from the selected profile
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

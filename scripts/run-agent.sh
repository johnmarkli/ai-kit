#!/usr/bin/env bash
set -euo pipefail

# Usage examples:
#   ./scripts/run-agent.sh --agent pi --task "debug failing tests" -- "help me fix this"
#   ./scripts/run-agent.sh --agent claude --task "review auth flow" -- "review this diff"
#   ./scripts/run-agent.sh --agent pi --dry-run --task "debug"
#
# Pass-through flags to underlying agent:
#   ./scripts/run-agent.sh --agent pi -- "help me fix this" -- --model openai/gpt-4o --print
#   ./scripts/run-agent.sh --agent claude -- "review this" -- --model sonnet --print

AGENT=""
TASK=""
PROMPT=""
DRY_RUN="false"
AGENT_ARGS=()

usage() {
  echo "Usage: $0 --agent <pi|claude> [--task <text>] [--dry-run] [-- <prompt> [-- <agent flags...>]]" >&2
}

require_value() {
  local opt="$1"
  local val="${2-}"
  if [[ -z "$val" || "$val" == --* ]]; then
    echo "Missing value for $opt" >&2
    usage
    exit 1
  fi
}

resolve_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$p"
  else
    # Best-effort fallback when neither realpath nor python3 is available.
    # Return the input path so callers can continue without hard failure.
    echo "$p"
  fi
}

warn_skills_link() {
  local tool_name="$1"
  local skills_link="$2"
  local expected_target="$3"
  local create_hint="$4"

  if [[ ! -e "$skills_link" ]]; then
    echo "Warning: $tool_name skills path missing: $skills_link" >&2
    echo "Create it with: $create_hint" >&2
    return
  fi

  if [[ ! -L "$skills_link" ]]; then
    echo "Warning: $skills_link exists but is not a symlink." >&2
    echo "Recommended: $create_hint" >&2
    return
  fi

  local resolved_link_target
  local resolved_expected_target
  resolved_link_target="$(resolve_path "$skills_link")"
  resolved_expected_target="$(resolve_path "$expected_target")"

  if [[ "$resolved_link_target" != "$resolved_expected_target" ]]; then
    echo "Warning: $skills_link points to '$resolved_link_target', expected '$resolved_expected_target'." >&2
  fi
}

print_dry_run() {
  local agent_name="$1"
  local skills_link="$2"
  local expected_target="$3"
  shift 3
  local -a cmd=("$@")

  echo "[dry-run] agent: $agent_name"
  echo "[dry-run] skills path: $skills_link"
  echo "[dry-run] expected skills target: $expected_target"
  echo "[dry-run] command: ${cmd[*]}"
  echo
  echo "[dry-run] composed context:"
  echo "----------------------------"
  cat "$CTX_FILE"
  echo "----------------------------"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      require_value "$1" "${2-}"
      AGENT="$2"
      shift 2
      ;;
    --task)
      require_value "$1" "${2-}"
      TASK="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --)
      shift
      REMAINING=("$@")
      SPLIT_INDEX=-1
      for i in "${!REMAINING[@]}"; do
        if [[ "${REMAINING[$i]}" == "--" ]]; then
          SPLIT_INDEX=$i
          break
        fi
      done

      if [[ $SPLIT_INDEX -ge 0 ]]; then
        PROMPT_PARTS=("${REMAINING[@]:0:$SPLIT_INDEX}")
        AGENT_ARGS=("${REMAINING[@]:$((SPLIT_INDEX + 1))}")
        PROMPT="${PROMPT_PARTS[*]}"
      else
        PROMPT="${REMAINING[*]}"
      fi
      break
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$AGENT" ]]; then
  usage
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_FILE="$ROOT_DIR/agents/AGENTS.core.md"
ALL_SKILLS_DIR="$ROOT_DIR/skills"

if [[ ! -f "$CORE_FILE" ]]; then
  echo "Missing core file: $CORE_FILE" >&2
  exit 1
fi

CTX_FILE="$(mktemp /tmp/agent-context.XXXXXX.md)"
trap 'rm -f "$CTX_FILE"' EXIT

{
  echo "# Runtime Agent Context"
  echo
  echo "## Core Instructions"
  cat "$CORE_FILE"
  echo

  if [[ -n "$TASK" ]]; then
    echo "## Task"
    echo "$TASK"
    echo
  fi
} > "$CTX_FILE"

case "$AGENT" in
  pi)
    PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
    PI_SKILLS_LINK="$PI_AGENT_DIR/skills"
    PI_CREATE_HINT="mkdir -p \"$PI_AGENT_DIR\" && ln -sfn \"$ALL_SKILLS_DIR\" \"$PI_SKILLS_LINK\""

    warn_skills_link "Pi" "$PI_SKILLS_LINK" "$ALL_SKILLS_DIR" "$PI_CREATE_HINT"

    CMD=(pi --append-system-prompt "$(<"$CTX_FILE")")
    [[ ${#AGENT_ARGS[@]} -gt 0 ]] && CMD+=("${AGENT_ARGS[@]}")
    [[ -n "$PROMPT" ]] && CMD+=("$PROMPT")

    if [[ "$DRY_RUN" == "true" ]]; then
      print_dry_run "pi" "$PI_SKILLS_LINK" "$ALL_SKILLS_DIR" "${CMD[@]}"
      exit 0
    fi

    "${CMD[@]}"
    ;;

  claude)
    CLAUDE_SKILLS_LINK="$HOME/.claude/skills"
    CLAUDE_CREATE_HINT="mkdir -p ~/.claude && ln -sfn \"$ALL_SKILLS_DIR\" ~/.claude/skills"

    warn_skills_link "Claude" "$CLAUDE_SKILLS_LINK" "$ALL_SKILLS_DIR" "$CLAUDE_CREATE_HINT"

    CMD=(claude --append-system-prompt "$(<"$CTX_FILE")")
    [[ ${#AGENT_ARGS[@]} -gt 0 ]] && CMD+=("${AGENT_ARGS[@]}")
    [[ -n "$PROMPT" ]] && CMD+=("$PROMPT")

    if [[ "$DRY_RUN" == "true" ]]; then
      print_dry_run "claude" "$CLAUDE_SKILLS_LINK" "$ALL_SKILLS_DIR" "${CMD[@]}"
      exit 0
    fi

    "${CMD[@]}"
    ;;

  *)
    echo "Unsupported agent: $AGENT (expected: pi|claude)" >&2
    exit 1
    ;;
esac

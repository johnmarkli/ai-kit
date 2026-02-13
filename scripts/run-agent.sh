#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSINFO:-}" || "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "This script requires bash 4+ (found: ${BASH_VERSION:-unknown})." >&2
  exit 1
fi

# Usage examples:
#   ./scripts/run-agent.sh --agent pi -- "help me fix this"
#   ./scripts/run-agent.sh --agent pi --profile go -- "fix failing go tests"
#   ./scripts/run-agent.sh --agent claude --list-profiles
#
# Pass-through flags to underlying agent:
#   ./scripts/run-agent.sh --agent pi --profile go -- "help" -- --model openai/gpt-4o --print

AGENT=""
PROMPT=""
DRY_RUN="false"
LIST_PROFILES="false"
PROFILE=""
AGENT_ARGS=()
PROFILE_FILES=()

declare -A VISITING=()
declare -A VISITED=()

usage() {
  echo "Usage: $0 --agent <pi|claude> [--profile <name>] [--list-profiles] [--dry-run] [-- <prompt> [-- <agent flags...>]]" >&2
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
  else
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

require_yq() {
  if ! command -v yq >/dev/null 2>&1; then
    echo "yq is required to parse profiles YAML (v4 expected)." >&2
    exit 1
  fi
}

list_profiles() {
  local config_file="$1"
  yq -r '.profiles | keys | .[]' "$config_file"
}

profile_exists() {
  local config_file="$1"
  local name="$2"
  NAME="$name" yq -r '.profiles[strenv(NAME)] | type' "$config_file"
}

resolve_profile() {
  local config_file="$1"
  local name="$2"

  if [[ -n "${VISITED[$name]:-}" ]]; then
    return
  fi

  if [[ -n "${VISITING[$name]:-}" ]]; then
    echo "Cycle detected in profile inheritance at '$name'" >&2
    exit 1
  fi

  local exists_type
  exists_type="$(profile_exists "$config_file" "$name")"
  if [[ "$exists_type" == "!!null" || "$exists_type" == "null" ]]; then
    echo "Profile '$name' not found" >&2
    exit 1
  fi

  VISITING["$name"]=1

  local parent
  parent="$(NAME="$name" yq -r '.profiles[strenv(NAME)].extends // ""' "$config_file")"
  if [[ -n "$parent" ]]; then
    resolve_profile "$config_file" "$parent"
  fi

  mapfile -t files < <(NAME="$name" yq -r '.profiles[strenv(NAME)].files[]?' "$config_file")
  if [[ ${#files[@]} -gt 0 ]]; then
    PROFILE_FILES+=("${files[@]}")
  fi

  unset VISITING["$name"]
  VISITED["$name"]=1
}

resolve_profile_files() {
  local config_file="$1"
  local requested_profile="$2"

  local selected_profile
  if [[ -n "$requested_profile" ]]; then
    selected_profile="$requested_profile"
  else
    selected_profile="$(yq -r '.default_profile // ""' "$config_file")"
  fi

  if [[ -z "$selected_profile" ]]; then
    echo "No profile provided and default_profile missing in config" >&2
    exit 1
  fi

  resolve_profile "$config_file" "$selected_profile"
}

print_dry_run() {
  local agent_name="$1"
  local skills_link="$2"
  local expected_target="$3"
  shift 3
  local -a cmd=("$@")

  echo "[dry-run] agent: $agent_name"
  echo "[dry-run] profile: ${PROFILE:-<default>}"
  echo "[dry-run] profiles config: $PROFILES_FILE"
  echo "[dry-run] resolved context files:"
  for f in "${RESOLVED_FILES[@]}"; do
    echo "  - $f"
  done
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
    --profile)
      require_value "$1" "${2-}"
      PROFILE="$2"
      shift 2
      ;;
    --list-profiles)
      LIST_PROFILES="true"
      shift
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
ALL_SKILLS_DIR="$ROOT_DIR/skills"
PROFILES_FILE="$ROOT_DIR/agents/profiles.yaml"

if [[ ! -f "$PROFILES_FILE" ]]; then
  echo "Missing profiles config: $PROFILES_FILE" >&2
  exit 1
fi

require_yq

if [[ "$LIST_PROFILES" == "true" ]]; then
  list_profiles "$PROFILES_FILE"
  exit 0
fi

resolve_profile_files "$PROFILES_FILE" "$PROFILE"

declare -A SEEN=()
RESOLVED_FILES=()
for f in "${PROFILE_FILES[@]}"; do
  [[ -n "$f" ]] || continue
  abs="$ROOT_DIR/$f"
  if [[ ! -f "$abs" ]]; then
    echo "Context file not found: $f (resolved: $abs)" >&2
    exit 1
  fi
  if [[ -n "${SEEN[$f]:-}" ]]; then
    continue
  fi
  SEEN["$f"]=1
  RESOLVED_FILES+=("$f")
done

if [[ ${#RESOLVED_FILES[@]} -eq 0 ]]; then
  echo "No context files resolved. Check profile settings." >&2
  exit 1
fi

CTX_FILE="$(mktemp /tmp/agent-context.XXXXXX.md)"
trap 'rm -f "$CTX_FILE"' EXIT

{
  echo "# Runtime Agent Context"
  echo
  for rel in "${RESOLVED_FILES[@]}"; do
    echo "## Source: $rel"
    cat "$ROOT_DIR/$rel"
    echo
  done
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

#!/usr/bin/env bash
# start-task-agent — new git worktree + herdr workspace + `run-agent` seeded with a prompt file.
#
# Usage:
#   start-task-agent.sh --repo <dir> --branch <name> --prompt-file <file> \
#       [--profile <name>] [--agent <pi|claude|omp>] [--label <text>] \
#       [--remote <name>] [--base <ref>] [--focus] [--dry-run]
#
# Prints a JSON summary (workspace, pane, worktree path, branch) on success.
set -euo pipefail

die() { echo "start-task-agent: $*" >&2; exit 1; }

REPO="" BRANCH="" PROMPT_FILE="" PROFILE="default" AGENT="pi" LABEL=""
REMOTE="" BASE="" FOCUS="--no-focus" DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --remote) REMOTE="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --focus) FOCUS="--focus"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[ "${HERDR_ENV:-}" = 1 ] || die "not running inside a herdr pane (HERDR_ENV!=1)"
command -v herdr >/dev/null || die "herdr not on PATH"
command -v run-agent >/dev/null || die "run-agent not on PATH (run ~/dev/ai-kit/scripts/install.sh)"
command -v jq >/dev/null || die "jq not on PATH"
[ -n "$REPO" ] && [ -n "$BRANCH" ] && [ -n "$PROMPT_FILE" ] || die "--repo, --branch, --prompt-file are required"
REPO="$(cd "$REPO" && git rev-parse --show-toplevel)" || die "not a git repo: $REPO"
PROMPT_FILE="$(cd "$(dirname "$PROMPT_FILE")" && pwd)/$(basename "$PROMPT_FILE")"
[ -s "$PROMPT_FILE" ] || die "prompt file missing or empty: $PROMPT_FILE"
profiles="$(run-agent --list-profiles)"
grep -qx "$PROFILE" <<<"$profiles" || die "unknown run-agent profile: $PROFILE"

# Remote: explicit > `fork` (upstream in fork-based setups) > `origin`.
if [ -z "$REMOTE" ]; then
  if git -C "$REPO" remote | grep -qx fork; then REMOTE=fork; else REMOTE=origin; fi
fi
if [ -z "$BASE" ]; then
  default_branch="$(git -C "$REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s#^$REMOTE/##" || true)"
  BASE="$REMOTE/${default_branch:-main}"
fi
LABEL="${LABEL:-$BRANCH}"

if git -C "$REPO" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  die "branch already exists: $BRANCH (pick another name or open the existing worktree with 'herdr worktree open')"
fi

printf -v AGENT_CMD 'run-agent --agent %q --profile %q -- "$(cat %q)"' "$AGENT" "$PROFILE" "$PROMPT_FILE"

if [ "$DRY_RUN" = 1 ]; then
  echo "repo:    $REPO"
  echo "fetch:   git fetch $REMOTE ${BASE#"$REMOTE"/}"
  echo "create:  herdr worktree create --cwd $REPO --branch $BRANCH --base $BASE --label $LABEL $FOCUS"
  echo "run:     $AGENT_CMD"
  exit 0
fi

git -C "$REPO" fetch --quiet "$REMOTE" "${BASE#"$REMOTE"/}" || die "git fetch $REMOTE failed"

wt_json="$(herdr worktree create --cwd "$REPO" --branch "$BRANCH" --base "$BASE" --label "$LABEL" $FOCUS)"
pane_id="$(jq -r '.result.root_pane.pane_id // empty' <<<"$wt_json")"
ws_id="$(jq -r '.result.workspace.workspace_id // empty' <<<"$wt_json")"
wt_path="$(jq -r '.result.worktree.path // empty' <<<"$wt_json")"
[ -n "$pane_id" ] || die "worktree create returned no pane: $wt_json"

# Fresh panes need a moment to reach an interactive shell prompt.
sleep 2
herdr pane run "$pane_id" "$AGENT_CMD" >/dev/null

jq -n --arg ws "$ws_id" --arg pane "$pane_id" --arg path "$wt_path" --arg branch "$BRANCH" \
  --arg base "$BASE" --arg base_sha "$(git -C "$REPO" rev-parse --short "$BASE")" \
  --arg profile "$PROFILE" --arg agent "$AGENT" --arg prompt "$PROMPT_FILE" \
  '{workspace_id:$ws, pane_id:$pane, worktree:$path, branch:$branch, base:$base, base_sha:$base_sha, agent:$agent, profile:$profile, prompt_file:$prompt}'

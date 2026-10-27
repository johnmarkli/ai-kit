#!/usr/bin/env bash
# Launch only. The calling agent submits the review prompt and waits explicitly.
set -euo pipefail

die() { echo "start-review: $*" >&2; exit 1; }
PROMPT_FILE=""
CONTEXT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file|--context-file)
      [[ -n "${2:-}" ]] || die "missing value for $1"
      case "$1" in
        --prompt-file) PROMPT_FILE="$2" ;;
        --context-file) CONTEXT_FILE="$2" ;;
      esac
      shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "${HERDR_ENV:-}" = 1 ]] || die "not running inside herdr"
[[ -n "${HERDR_PANE_ID:-}" ]] || die "HERDR_PANE_ID is required"
[[ -n "${PI_SESSION_FILE:-}" && -r "$PI_SESSION_FILE" && -s "$PI_SESSION_FILE" ]] ||
  die "PI_SESSION_FILE must identify the current persistent pi session; never guess with --continue"
[[ -s "$PROMPT_FILE" && -r "$PROMPT_FILE" ]] || die "readable --prompt-file is required"
[[ -s "$CONTEXT_FILE" && -r "$CONTEXT_FILE" ]] || die "readable --context-file is required"
for cmd in herdr pi jq run-agent; do
  command -v "$cmd" >/dev/null || die "$cmd not on PATH"
done
models="$(pi --list-models gpt-6.1-sol)"
awk '$1 == "openai" && $2 == "gpt-6.1-sol" { found=1 } END { exit !found }' <<<"$models" ||
  die "openai/gpt-6.1-sol is unavailable; no fallback model will be selected"

# Never fork a file that the parent can still append to during reviewer startup.
# Keep snapshots private: they contain conversation history and runtime instructions.
umask 077
mkdir -p /tmp/review-and-plan
RUN_DIR="$(mktemp -d /tmp/review-and-plan/run.XXXXXXXX)"
PANE=""
on_exit() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "run_dir=$RUN_DIR" >&2
    [[ -z "$PANE" ]] || echo "reviewer pane=$PANE; inspect before retrying; left open for recovery" >&2
  fi
}
trap on_exit EXIT
cp -- "$PI_SESSION_FILE" "$RUN_DIR/parent.jsonl"
cp -- "$PROMPT_FILE" "$RUN_DIR/prompt.md"
cp -- "$CONTEXT_FILE" "$RUN_DIR/context.md"

split="$(herdr pane split --pane "$HERDR_PANE_ID" --direction right --cwd "$PWD" --no-focus)"
PANE="$(jq -er '.result.pane.pane_id' <<<"$split")"
# Herdr supports only right/down splits. Swap identities to put the reviewer left.
herdr pane swap --source-pane "$HERDR_PANE_ID" --target-pane "$PANE" >/dev/null
# run-agent's first -- introduces the prompt; the second introduces native flags.
# Skip wrapper updates so startup doesn't change installed packages mid-review.
CMD=(run-agent --profile indigo --agent pi --no-update -- "" --
  --fork "$RUN_DIR/parent.jsonl"
  --model openai/gpt-6.1-sol
  --append-system-prompt "$RUN_DIR/context.md")
printf -v command '%q ' "${CMD[@]}"
herdr pane run "$PANE" "$command" >/dev/null

# pane run acknowledges queuing, not agent readiness; the caller must check it.
jq -n --arg pane "$PANE" --arg parent "$HERDR_PANE_ID" \
  --arg dir "$RUN_DIR" --arg cwd "$PWD" \
  '{pane_id:$pane, parent_pane_id:$parent, agent:"pi", profile:"indigo", cwd:$cwd,
    launch_status:"queued", model:"openai/gpt-6.1-sol", run_dir:$dir,
    prompt_file:($dir + "/prompt.md")}'

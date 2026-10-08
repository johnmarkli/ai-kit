#!/usr/bin/env bash
# read-peer-review — dump the terminal output of the OTHER agents in this herdr
# workspace, so the calling agent can find a code review one of them wrote.
#
# Usage:
#   read-peer-review.sh [--pane <pane_id>] [--lines N] [--out-dir DIR]
#
# Without --pane, every agent pane in $HERDR_WORKSPACE_ID except $HERDR_PANE_ID is
# read. Each pane's output goes to <out-dir>/<pane_id>.txt. Prints JSON: one entry
# per pane with its agent, status, cwd, file, and whether it looks like a review.
set -euo pipefail

die() { echo "read-peer-review: $*" >&2; exit 1; }

PANE="" LINES=600 OUT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pane) PANE="$2"; shift 2 ;;
    --lines) LINES="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ "${HERDR_ENV:-}" = 1 ] || die "not running inside herdr (HERDR_ENV != 1)"
command -v herdr >/dev/null || die "herdr not on PATH"
command -v jq >/dev/null || die "jq not on PATH"
WS="${HERDR_WORKSPACE_ID:?HERDR_WORKSPACE_ID unset}"
SELF="${HERDR_PANE_ID:?HERDR_PANE_ID unset}"
OUT_DIR="${OUT_DIR:-/tmp/plan-review-response/${WS//:/-}}"
mkdir -p "$OUT_DIR"

agents_json="$(herdr agent list)"
if [ -n "$PANE" ]; then
  panes="$PANE"
else
  panes="$(jq -r --arg ws "$WS" --arg self "$SELF" \
    '.result.agents[] | select(.workspace_id == $ws and .pane_id != $self) | .pane_id' \
    <<<"$agents_json")"
fi
[ -n "$panes" ] || die "no other agent panes in workspace $WS"

# Markers a written review tends to contain. Loose on purpose; the caller decides.
REVIEW_RE='(^|[^A-Za-z])(Review|Findings|Blocking|Non-blocking|Severity|Recommendation|Approve|Request changes|LGTM)([^A-Za-z]|$)'

echo "["
first=1
for p in $panes; do
  file="$OUT_DIR/${p//:/-}.txt"
  herdr agent read "$p" --source recent-unwrapped --lines "$LINES" >"$file" 2>&1 || true
  hits="$(grep -E -c "$REVIEW_RE" "$file" || true)"
  meta="$(jq -c --arg p "$p" '.result.agents[] | select(.pane_id == $p)
    | {agent, agent_status, cwd}' <<<"$agents_json")"
  [ -n "$meta" ] || meta='{}'
  [ $first = 1 ] || echo ","
  first=0
  jq -nc --arg pane "$p" --arg file "$file" --argjson hits "${hits:-0}" --argjson meta "$meta" \
    '$meta + {pane_id: $pane, file: $file, review_marker_lines: $hits, looks_like_review: ($hits >= 3)}'
done
echo "]"

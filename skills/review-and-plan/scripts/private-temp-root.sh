#!/usr/bin/env bash
# Print a verified private root. An optional path must have a trusted parent
# (e.g. sticky /tmp or a caller-owned private directory); never follow symlinks.
set -euo pipefail

ROOT="${1:-/tmp/review-and-plan-$UID}"
[[ "$ROOT" = /* && ( "$ROOT" = / || "$ROOT" != */ ) ]] || {
  echo "private-temp-root: use an absolute path without a trailing slash" >&2
  exit 1
}
umask 077
# Atomic creation; an existing path must pass validation, never chmod/repair it.
mkdir -m 700 -- "$ROOT" 2>/dev/null || true
# One no-follow metadata check avoids checking symlink/owner/mode separately
# against potentially different objects in an attacker-controlled pathname.
[[ "$(find -P "$ROOT" -prune -type d -user "$UID" -perm 0700)" = "$ROOT" ]] || {
  echo "private-temp-root: require a directory owned by UID $UID with mode 0700, not a symlink: $ROOT" >&2
  exit 1
}
printf '%s\n' "$ROOT"

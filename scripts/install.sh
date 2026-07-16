#!/usr/bin/env bash
set -euo pipefail

# Installs run-agent.sh as a first-class `run-agent` command for the current user.
#
# Usage:
#   ./scripts/install.sh                 # install as ~/.local/bin/run-agent
#   ./scripts/install.sh --name foo      # install under a custom command name
#   ./scripts/install.sh --bin-dir DIR   # install into a custom (user-writable) dir
#   ./scripts/install.sh --uninstall     # remove the installed symlink

CMD_NAME="run-agent"
BIN_DIR="${HOME}/.local/bin"
UNINSTALL="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      [[ -n "${2-}" ]] || { echo "Missing value for --name" >&2; exit 1; }
      CMD_NAME="$2"; shift 2 ;;
    --bin-dir)
      [[ -n "${2-}" ]] || { echo "Missing value for --bin-dir" >&2; exit 1; }
      BIN_DIR="$2"; shift 2 ;;
    --uninstall)
      UNINSTALL="true"; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/run-agent.sh"
LINK="$BIN_DIR/$CMD_NAME"

if [[ ! -f "$TARGET" ]]; then
  echo "Cannot find run-agent.sh at: $TARGET" >&2
  exit 1
fi

if [[ "$UNINSTALL" == "true" ]]; then
  if [[ -L "$LINK" || -e "$LINK" ]]; then
    rm -f "$LINK"
    echo "Removed: $LINK"
  else
    echo "Nothing to remove at: $LINK"
  fi
  exit 0
fi

chmod +x "$TARGET"
mkdir -p "$BIN_DIR"

if [[ -e "$LINK" && ! -L "$LINK" ]]; then
  echo "Refusing to overwrite non-symlink: $LINK" >&2
  echo "Remove it manually or choose another --name / --bin-dir." >&2
  exit 1
fi

ln -sfn "$TARGET" "$LINK"
echo "Installed: $LINK -> $TARGET"

case ":$PATH:" in
  *":$BIN_DIR:"*)
    echo "Ready. Try: $CMD_NAME --list-profiles" ;;
  *)
    echo
    echo "Warning: $BIN_DIR is not on your PATH."
    echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    echo "Then restart your shell and run: $CMD_NAME --list-profiles" ;;
esac

#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TREE="$(CDPATH= cd -- "$PROJECT_DIR/.." && pwd)"

if [ "${1:-}" = "--tree" ]; then
	[ "$#" -ge 2 ] || { echo "--tree requires a directory" >&2; exit 2; }
	TREE="$2"
	shift 2
fi

"$SCRIPT_DIR/integrate.sh" --tree "$TREE"
exec make -C "$TREE" "$@"

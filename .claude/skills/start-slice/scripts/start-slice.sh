#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAP=$1
SPEC=$2
shift 2
exec python3 "$SCRIPT_DIR/../../_shared/delivery.py" "$MAP" "$SPEC" start "$@"

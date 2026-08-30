#!/usr/bin/env bash
# Action shim: actions run without a tty, so hand off to an overlay pane.
set -euo pipefail
herdr="${HERDR_BIN_PATH:-herdr}"
exec "$herdr" plugin pane open --plugin agents --entrypoint picker --placement overlay

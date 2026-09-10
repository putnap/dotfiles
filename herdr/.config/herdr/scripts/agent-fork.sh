#!/usr/bin/env bash
set -euo pipefail
helper=${AGENT_SETUP_DIR:-${HOME}/.config/agent-setup}/control.sh
if [[ ! -f $helper && -z ${AGENT_SETUP_DIR:-} ]]; then
  # This package may already be Stowed before the shared agents package is applied.
  script_dir=$(cd "$(dirname "$0")" && pwd -P)
  repo=$(cd "$script_dir/../../../.." && pwd -P)
  helper=$repo/agents/.config/agent-setup/control.sh
fi
exec bash "$helper" fork "${1:-pane}" "${@:2}"

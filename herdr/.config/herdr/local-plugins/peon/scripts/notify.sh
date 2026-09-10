#!/usr/bin/env bash
set -euo pipefail
exec bash "${AGENT_SETUP_DIR:-${HOME}/.config/agent-setup}/notify.sh" "${1:?expected seed or event}"

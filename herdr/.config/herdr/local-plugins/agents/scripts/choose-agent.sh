#!/usr/bin/env bash
set -euo pipefail
exec bash "${AGENT_SETUP_DIR:-${HOME}/.config/agent-setup}/control.sh" launch tab --choose

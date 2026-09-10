#!/usr/bin/env bash
# Idempotently layer the peon-ping tmux integration onto a stock peon-ping
# install. Safe to re-run; run it again after `peon-ping-setup` or `peon
# update`, both of which re-link peon.sh back to the stock engine.
set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks/peon-ping"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [ ! -f "$HOOK_DIR/config.json" ]; then
  echo "error: $HOOK_DIR not set up — run 'peon-ping-setup' first." >&2
  exit 1
fi

# 1. Point the peon-ping hook at our wrapper (replaces the stock symlink).
ln -sfn "$SELF_DIR/wrapper.sh" "$HOOK_DIR/peon.sh"
echo "linked $HOOK_DIR/peon.sh -> $SELF_DIR/wrapper.sh"

# 2. Set the tmux-aware notification title: "<session> - <window>".
python3 - "$HOOK_DIR/config.json" <<'PY'
import json, sys
path = sys.argv[1]
cfg = json.load(open(path))
want = "[ -n \"$TMUX_PANE\" ] && tmux display-message -p -t \"$TMUX_PANE\" '#S - #W'"
if cfg.get("notification_title_script") != want:
    cfg["notification_title_script"] = want
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print("set notification_title_script")
else:
    print("notification_title_script already correct")
PY

echo "peon-tmux integration applied."

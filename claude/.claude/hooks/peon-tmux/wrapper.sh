#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# peon-ping tmux wrapper — installed as ~/.claude/hooks/peon-ping/peon.sh.
# Delegates to the real engine (brew opt path, so it still tracks upgrades) and
# adds two tmux-aware behaviors:
#
#   1. Click-to-jump: exports PEON_CLICK_COMMAND so clicking a notification
#      raises Ghostty and switches tmux to the session + window that triggered
#      it (window-id based, survives reindexing). notify.sh reads
#      PEON_CLICK_COMMAND from the env and runs it via `bash -lc` on click.
#
#   2. Always-show banners: peon's Ghostty focus check can't see inside tmux —
#      it falls back to comparing cwd, which suppresses the banner whenever the
#      focused Ghostty window shares a cwd with (or is simply in front of) the
#      pinging one. We blank the event cwd so peon never suppresses on that
#      basis; banners always show while in tmux. (Title still resolves via
#      notification_title_script, which uses tmux.)
#
#      Trade-off: you also get a banner for the pane you're currently looking
#      at. Reliable "am I viewing this exact pane?" detection isn't possible
#      from a tmux hook — a Claude window reads as active-in-its-session even
#      when you're elsewhere in Ghostty — so we err toward never dropping a
#      notification.
#
# Revert: run `peon-ping-setup`, or:
#   ln -sf /opt/homebrew/opt/peon-ping/libexec/peon.sh ~/.claude/hooks/peon-ping/peon.sh
# ─────────────────────────────────────────────────────────────────────────────
export PEON_REAL="/opt/homebrew/opt/peon-ping/libexec/peon.sh"

# Outside tmux (or tmux missing) → behave exactly like stock peon-ping.
if [ -z "${TMUX_PANE:-}" ] || ! command -v tmux >/dev/null 2>&1; then
  exec bash "$PEON_REAL" "$@"
fi

TMUX_BIN="$(command -v tmux)"

# (1) Bake the click target for THIS pane: switch client to its session, then
#     select its window by id. Runs via `bash -lc` when the banner is clicked.
PEON_TMUX_SWITCH="$("$TMUX_BIN" display-message -p -t "$TMUX_PANE" \
  "${TMUX_BIN} switch-client -t #{q:session_name}; ${TMUX_BIN} select-window -t #{window_id}" 2>/dev/null)"

# Raise Ghostty as part of the click. The overlay's own handler tries to focus
# the terminal with NSRunningApplication activateWithOptions(...IgnoringOtherApps),
# but macOS 14+ ignores that cross-app activation when a *different* app is
# frontmost — so clicking from another app switched tmux invisibly and never
# brought Ghostty forward. `open -b` goes through LaunchServices, which raises
# the app reliably from any frontmost app (no-op when Ghostty already has focus,
# and never spawns a new window). Runs before the tmux switch in the same
# `bash -lc`.
export PEON_CLICK_COMMAND="open -b com.mitchellh.ghostty; ${PEON_TMUX_SWITCH}"

# (2) Blank the event cwd so peon's cwd-based focus heuristic can't suppress the
#     banner, then hand the modified event to the real engine.
exec python3 -c '
import sys, json, os, subprocess
raw = sys.stdin.read()
try:
    ev = json.loads(raw)
    ev["cwd"] = ""
    ev.pop("workspace_roots", None)
    raw = json.dumps(ev)
except Exception:
    pass
# Detach into a new session (start_new_session) so Claude Code reaping the hook
# process group cannot kill the async sound/overlay before it renders.
sys.exit(subprocess.run(["bash", os.environ["PEON_REAL"]], input=raw, text=True,
                        start_new_session=True).returncode)
'

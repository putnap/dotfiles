#!/usr/bin/env bash
# Install zen-keyboard-shortcuts.json into the live Zen profile.
#
# Zen rewrites this file wholesale whenever a shortcut is changed in its UI, so
# it is copied rather than symlinked -- a link would be replaced by a regular
# file on the first edit. Run `--pull` after changing shortcuts in the UI to
# bring them back here.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo="$here/zen-keyboard-shortcuts.json"
profile=$(ls -d ~/Library/Application\ Support/zen/Profiles/*release*/ 2>/dev/null | head -1)
[ -n "$profile" ] || { echo "no Zen release profile found" >&2; exit 1; }
live="${profile}zen-keyboard-shortcuts.json"

# Zen holds this file open and flushes its own copy on exit, which would
# silently discard whatever we wrote.
if pgrep -x zen >/dev/null; then
  echo "Zen is running -- quit it first, or it will overwrite this on exit." >&2
  exit 1
fi

if [ "${1:-}" = "--pull" ]; then
  cp "$live" "$repo"
  echo "pulled  $live -> $repo"
else
  cp "$live" "$live.bak"
  cp "$repo" "$live"
  echo "pushed  $repo -> $live   (previous saved as $live.bak)"
fi

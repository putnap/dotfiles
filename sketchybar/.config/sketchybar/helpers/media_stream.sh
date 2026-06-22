#!/usr/bin/env bash
# Feed sketchybar's media widget from media-control's event stream.
#
# macOS 15.4+/Tahoe gutted sketchybar's built-in `media_change` event: Apple
# gated the private MediaRemote *subscribe* API, so unsigned apps no longer
# receive now-playing notifications. media-control ships a `mediaremote-adapter`
# that restores them. We stream those changes and forward each one to sketchybar
# as a custom `media_update` event.
#
# Launched by items/media.lua on every sketchybar load. Singleton: a new
# instance terminates the previous one (recorded in PIDFILE) and its stream
# child, so reloads don't pile up duplicates.

PIDFILE=/tmp/sketchybar_media_stream.pid

# Replace any previous instance (kill by recorded PID — never a broad pattern).
[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
echo $$ > "$PIDFILE"

FIFO="$(mktemp -u /tmp/sketchybar_media_fifo.XXXXXX)"
mkfifo "$FIFO" 2>/dev/null || exit 1

stream_pid=""
cleanup() {
  trap - INT TERM EXIT          # disarm so cleanup can't re-enter itself
  [ -n "$stream_pid" ] && kill "$stream_pid" 2>/dev/null
  rm -f "$FIFO"
  exit 0
}
trap cleanup INT TERM EXIT

art_toggle=0
art_path=""
last_title=""

while true; do
  # --no-diff: each line carries full metadata (no diff-merging needed)
  # --no-artwork: keep events tiny; artwork is fetched separately on track change
  # --debounce: coalesce rapid play/pause bursts
  media-control stream --no-diff --no-artwork --debounce=150 > "$FIFO" 2>/dev/null &
  stream_pid=$!

  while IFS= read -r line; do
    IFS=$'\t' read -r playing title artist app < <(
      printf '%s' "$line" | jq -r '[(.payload.playing // false | tostring), (.payload.title // ""), (.payload.artist // ""), (.payload.bundleIdentifier // "")] | @tsv' 2>/dev/null
    )

    # media-control emits empty `{}` sentinel events; forwarding them would
    # flicker the widget off. A real play/pause always carries a title.
    [ -z "$title" ] && continue

    # Refresh artwork only on track change. Alternate the filename so the path
    # string changes too — otherwise sketchybar caches the old image by path.
    if [ "$title" != "$last_title" ]; then
      last_title="$title"
      art_toggle=$(( (art_toggle + 1) % 2 ))
      art_path="/tmp/sketchybar_media_art_${art_toggle}"
      media-control get 2>/dev/null | jq -r '.artworkData // empty' \
        | openssl base64 -d -A > "$art_path" 2>/dev/null
      # Cover art is full-resolution (~600px). Downscale so the item's scale
      # renders it at bar size instead of filling the screen.
      [ -s "$art_path" ] && sips -Z 100 "$art_path" >/dev/null 2>&1
      [ -s "$art_path" ] || art_path=""
    fi

    sketchybar --trigger media_update \
      PLAYING="$playing" TITLE="$title" ARTIST="$artist" APP="$app" ART="$art_path"
  done < "$FIFO"

  # stream ended (adapter restart / sleep-wake) — reconnect after a short pause
  kill "$stream_pid" 2>/dev/null
  sleep 2
done

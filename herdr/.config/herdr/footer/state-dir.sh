# Shared by the collector and Claude callback. Preview paths remain overridable.
if [[ -n ${HERDR_FOOTER_STATE_DIR:-} ]]; then
  root=$HERDR_FOOTER_STATE_DIR
else
  socket_key=$(printf '%s' "${HERDR_SOCKET_PATH:?}" | shasum -a 256 | cut -d ' ' -f 1)
  root=${XDG_STATE_HOME:-$HOME/.local/state}/herdr/footer/$socket_key
fi

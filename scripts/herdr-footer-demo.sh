#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
root=${HERDR_FOOTER_PREVIEW_DIR:-/tmp/herdr-footer-${USER:?}-v5}
export HERDR_CONFIG_PATH=$root/config.toml HERDR_SOCKET_PATH=$root/herdr.sock
export XDG_CONFIG_HOME=$root/xdg XDG_STATE_HOME=$root/state XDG_DATA_HOME=$root/data XDG_CACHE_HOME=$root/cache
export HERDR_FOOTER_STATE_DIR=$root/metrics
unset HERDR_CLIENT_SOCKET_PATH HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID CODEX_THREAD_ID
# Automation may disable color for tool output; the interactive preview must not inherit that.
unset NO_COLOR
binary=$root/build/bin/herdr
configure() {
  mkdir -p "$root"
  local next
  next=$(mktemp "$root/.config.XXXXXX")
  if ! dasel -i toml -o json < "$repo/herdr/.config/herdr/config.toml" |
    jq --slurpfile footer <(dasel -i toml -o json < "$repo/herdr/.config/herdr/pane-footer.toml") '{onboarding:false,theme,keys:(.keys|.command |= map(select(.type != "plugin_action"))),session,
      ui:{pane_borders:"always",pane_footer:$footer[0],toast:{delivery:"off"},sound:{enabled:false}},
      terminal:{default_shell:"/bin/zsh",shell_mode:"login"},experimental:(.experimental + {allow_nested:true})}' |
    dasel -i json -o toml > "$next" ||
    ! HERDR_CONFIG_PATH="$next" "$binary" config check; then
    rm -f "$next"
    return 1
  fi
  mv "$next" "$HERDR_CONFIG_PATH"
  # Concrete callback paths survive native agent restore (plugin env is not saved).
  mkdir -p "$root/plugin"
  for file in "$repo/herdr/.config/herdr/footer/"*; do
    [[ ${file##*/} == herdr-plugin.toml ]] || ln -sfn "$file" "$root/plugin/${file##*/}"
  done
  dasel -i toml -o json < "$repo/herdr/.config/herdr/footer/herdr-plugin.toml" |
    jq --arg scripts "$repo/herdr/.config/herdr/footer" '.panes[].command[] |= gsub("\\$HERDR_PLUGIN_ROOT"; $scripts)' |
    dasel -i json -o toml > "$root/plugin/herdr-plugin.toml"
}
live() {
  "$binary" plugin link "$root/plugin" --enabled >/dev/null
  "$binary" plugin action invoke collect --plugin agent-footer-preview >/dev/null
  workspace=$("$binary" workspace create --cwd "$repo" --label 'Live footer preview' --focus | jq -er '.result.root_pane.workspace_id')
  first=$("$binary" plugin pane open --plugin agent-footer-preview --entrypoint claude --workspace "$workspace" --placement tab \
    --env "HERDR_FOOTER_STATE_DIR=$root/metrics" --cwd "$repo" --focus | jq -er '.result.plugin_pane.pane.pane_id')
  "$binary" plugin pane open --plugin agent-footer-preview --entrypoint codex --target-pane "$first" --placement split --direction right \
    --env "HERDR_FOOTER_STATE_DIR=$root/metrics" --cwd "$repo" --focus >/dev/null
}
case ${1:-attach} in
  build)
    mkdir -p "$root"
    cd "$repo"
    exec nix build --impure --file nix/.config/nix/footer-preview.nix --out-link "$root/build";;
  start)
    [[ -x $binary ]] || { echo "Run: bash $repo/scripts/herdr-footer-demo.sh build" >&2; exit 1; }
    configure
    if [[ -S $HERDR_SOCKET_PATH ]]; then
      "$binary" server reload-config
    else
      nohup "$binary" server > "$root/server.log" 2>&1 &
      echo "$!" > "$root/server.pid"
      for ((i=0;i<100;i++)); do [[ ! -S $HERDR_SOCKET_PATH ]] || break; sleep 0.1; done
    fi
    live
    echo "Preview ready. Attach: bash $repo/scripts/herdr-footer-demo.sh attach";;
  configure) configure;;
  reload) configure; "$binary" server reload-config;;
  live) live;;
  attach) exec "$binary";;
  stop) "$binary" server stop;;
  *) echo 'Usage: herdr-footer-demo.sh build|configure|start|live|reload|attach|stop' >&2; exit 1;;
esac

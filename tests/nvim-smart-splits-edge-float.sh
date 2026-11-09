#!/usr/bin/env bash
# From the snacks explorer at the screen's left edge, ctrl+h must leave nvim through at_edge:
# smart-splits v2 skips at_edge for such floats, and herdr-app only hears about the edge from it.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/nvim-smart-splits.XXXXXX)
sock=$scratch/nvim.sock
echo text > "$scratch/a.txt"
(cd "$scratch" && XDG_CONFIG_HOME=$repo/nvim/.config XDG_STATE_HOME=$scratch/state HC_TERMINAL_ID=test \
  nvim --headless --listen "$sock" a.txt > "$scratch/nvim.log" 2>&1) &
nvim_pid=$!
cleanup() {
  kill "$nvim_pid" 2>/dev/null || true
  wait "$nvim_pid" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
for ((i=0;i<100;i++)); do
  [[ ! -S $sock ]] || break
  sleep 0.1
done

lua() { nvim --server "$sock" --remote-expr "luaeval('$1')"; }
run() { lua "(function() $1 end)()" >/dev/null; }
press() { nvim --server "$sock" --remote-send "$1"; sleep 0.5; }
expect() {
  local want=$1 got=$2 what=$3
  [[ $got == "$want" ]] || { echo "$what: expected $want, got $got" >&2; exit 1; }
}

# Headless nvim has no UI, so LazyVim's VeryLazy (which loads the keymaps) never fires on its own.
run 'vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })'
# Record the edge instead of running herdr-app, then open the explorer; it takes the focus.
run 'require("smart-splits.config").at_edge = function(ctx) vim.g.edges = (vim.g.edges or "") .. ctx.direction end'
run 'Snacks.explorer()'
run 'vim.wait(3000, function() return vim.bo.filetype == "snacks_picker_list" end)'
expect snacks_picker_list "$(lua 'vim.bo.filetype')" 'explorer focused'

press '<C-h>'
expect left "$(lua 'vim.g.edges')" 'explorer -> left edge'

press '<C-l>'
expect text "$(lua 'vim.bo.filetype')" 'explorer -> file on the right'
press '<C-h>'
expect snacks_picker_list "$(lua 'vim.bo.filetype')" 'file -> explorer'
expect left "$(lua 'vim.g.edges')" 'no edge between nvim windows'
echo ok

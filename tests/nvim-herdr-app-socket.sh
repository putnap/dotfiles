#!/usr/bin/env bash
# In herdr-app, nvim listens on a socket named after its terminal, so herdr-app's keys mod can send
# ctrl+hjkl without hc keys' wait; a socket left by a killed nvim must not block the next one.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/nvim-herdr-app.XXXXXX)
socket=$scratch/state/nvim/hc/t-test.sock
echo text > "$scratch/a.txt"
cleanup() {
  [[ -z ${nvim_pid:-} ]] || kill "$nvim_pid" 2>/dev/null || true
  wait 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT

# A killed nvim's socket: the file stays, nothing listens.
mkdir -p "$(dirname "$socket")"
python3 -I -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$socket"

(cd "$scratch" && XDG_CONFIG_HOME=$repo/nvim/.config XDG_STATE_HOME=$scratch/state HC_TERMINAL_ID=t-test \
  nvim --headless -O a.txt a.txt > "$scratch/nvim.log" 2>&1) &
nvim_pid=$!

lua() { nvim --server "$socket" --remote-expr "luaeval('$1')"; }
expect() {
  local want=$1 got=$2 what=$3
  [[ $got == "$want" ]] || { echo "$what: expected $want, got $got" >&2; exit 1; }
}
for ((i=0;i<100;i++)); do
  lua '1' >/dev/null 2>&1 && break
  sleep 0.1
done
expect 1 "$(lua '1')" 'nvim listens on the stale socket path'

# Headless nvim has no UI, so LazyVim's VeryLazy (which loads the keymaps) never fires on its own.
lua '(function() vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" }) end)()' >/dev/null
expect 1 "$(lua 'vim.fn.winnr()')" 'starts in the left window'
nvim --server "$socket" --remote-send '<C-l>'
sleep 0.5
expect 2 "$(lua 'vim.fn.winnr()')" 'ctrl+l through the socket'
echo ok

#!/usr/bin/env bash
set -euo pipefail
unset HERDR_SOCKET_PATH HERDR_PANE_ID CODEX_THREAD_ID
case ${1:?} in
  start)
    command -v workmux >/dev/null || exit 0
    config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/workmux
    dasel -i yaml -o json < "$config_dir/defaults.yaml" |
      python3 -c '
import json, os, subprocess, sys, tempfile
from pathlib import Path
config = json.load(sys.stdin)
def style(option):
    value = subprocess.check_output(["tmux", "display-message", "-p", "#{E:" + option + "}"], text=True).strip()
    return dict(part.split("=", 1) for part in value.split(",") if "=" in part)
normal, active = style("status-style"), style("window-status-current-style")
colors = {}
fields = dict(current_row_bg="surface_0", highlight_row_bg="surface_1", current_worktree_fg="green",
              text="fg", dimmed="subtext_0", border="surface_0", help_border="surface_1",
              help_muted="subtext_0", header="mauve", keycap="blue", info="blue",
              success="green", warning="yellow", danger="red", accent="mauve")
for field, option in fields.items():
    value = subprocess.check_output(["tmux", "show-options", "-gqv", "@thm_" + option], text=True).strip()
    if not value:
        source = active if field in ("highlight_row_bg", "accent", "current_worktree_fg") else normal
        value = source.get("bg" if field.endswith("_bg") else "fg", "")
    if value and value != "default":
        colors[field] = value.replace("colour", "")
config["theme"] = {"custom": colors}
flavor = subprocess.check_output(["tmux", "show-options", "-gqv", "@catppuccin_flavor"], text=True).strip()
if flavor:
    config["theme"]["mode"] = "light" if flavor == "latte" else "dark"
path = Path(sys.argv[1]) / "config.yaml"
content = json.dumps(config, indent=2) + "\n"
if not path.exists() or path.read_text() != content:
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as temporary:
        temporary.write(content)
    os.replace(temporary.name, path)
' "$config_dir"
    scripts=$HOME/.config/herdr/footer
    source "$scripts/state-dir.sh"
    mkdir -p "$root"
    bash "$scripts/collect.sh" --tmux >> "$root/collector.log" 2>&1 &
    ;;
  restore-sidebars)
    source "$HOME/.tmux/plugins/tmux-resurrect/scripts/helpers.sh"
    while IFS=$'\t' read -r kind session window _ _ pane _ _ _ _ command; do
      if [[ $kind == pane && $command == ':workmux _sidebar-run' ]]; then
        tmux set-option -p -t "=$session:$window.$pane" @workmux_role sidebar
      fi
    done < "$(last_resurrect_file)"
    ;;
  finish-restore)
    tmux set-option -gu @workmux_restoring
    if tmux list-panes -a -F '#{@workmux_role}' | rg -q '^sidebar$'; then
      workmux sidebar on
    fi
    ;;
  save)
    python3 - "${2:?}" "$(dirname "$0")/agent-fork.sh" <<'PYTHON'
from pathlib import Path
import shlex
import subprocess
import sys
path = Path(sys.argv[1])
rows = []
for line in path.read_text().splitlines():
    fields = line.split("\t")
    if fields[0] == "pane":
        target = f"={fields[1]}:{fields[2]}.{fields[5]}"
        if fields[9] in ("nvim", "vim", "vi"):
            fields[10] = ":" + fields[9]
        role = subprocess.check_output(["tmux", "show-options", "-pqv", "-t", target, "@workmux_role"], text=True).strip()
        if role == "sidebar":
            fields[10] = ":workmux _sidebar-run"
        record = subprocess.check_output(["tmux", "show-options", "-pqv", "-t", target, "@workmux_hook"], text=True).strip()
        if record:
            result = subprocess.run(["bash", sys.argv[2], "resume-command", target], text=True, capture_output=True)
            if result.returncode == 0:
                resumed = shlex.split(result.stdout)
                original = iter(shlex.split(fields[10][1:])[1:])
                value_flags = {"-c", "--config", "-m", "--model", "-p", "--profile", "-s", "--sandbox",
                               "-a", "--ask-for-approval", "--settings", "--effort"}
                if resumed[0] == "claude":
                    value_flags -= {"-p", "--profile", "-c", "--config", "-s", "--sandbox", "-a", "--ask-for-approval"}
                switches = {"--dangerously-skip-permissions", "--yolo", "--full-auto",
                            "--dangerously-bypass-approvals-and-sandbox", "--no-alt-screen"}
                for argument in original:
                    flag = argument.split("=", 1)[0]
                    if flag in switches or (flag in value_flags and "=" in argument):
                        resumed.append(argument)
                    elif flag in value_flags:
                        value = next(original, None)
                        if value is not None:
                            resumed.extend((argument, value))
                fields[10] = ":" + shlex.join(resumed)
    rows.append("\t".join(fields))
path.write_text("\n".join(rows) + "\n")
PYTHON
    ;;
  new)
    read -r -p 'Branch: ' branch
    [[ -n $branch ]] || exit 0
    read -r -p 'Base ref (empty = current): ' base
    read -r -p 'Directory name (empty = branch name): ' name
    args=(add "$branch")
    [[ -z $base ]] || args+=(--base "$base")
    [[ -z $name ]] || args+=(--name "$name")
    workmux "${args[@]}"
    ;;
  open)
    path=$(git worktree list --porcelain | sed -n 's/^worktree //p' | fzf --prompt='worktree> ') || exit 0
    cd "$path"
    workmux open "$(basename "$path")"
    ;;
  launch|choose)
    action=$1; placement=${2:-window}
    agent=$(dasel -i yaml -o json < "$HOME/.config/workmux/defaults.yaml" | jq -er '.agent')
    if [[ $action == choose ]]; then
      agent=$(printf 'codex\nclaude\n' | fzf --prompt='agent> ') || exit 0
    fi
    case "$agent" in claude|codex) ;; *) echo "Unsupported launcher agent: $agent" >&2; exit 1;; esac
    command=("$agent")
    [[ $agent != claude ]] || command+=(--dangerously-skip-permissions)
    if [[ $placement == pane ]]; then tmux split-window -h -c "$PWD" "${command[@]}"
    else tmux new-window -c "$PWD" "${command[@]}"; fi
    ;;
  *) echo 'Expected start, save, restore-sidebars, finish-restore, new, open, launch or choose' >&2; exit 2;;
esac

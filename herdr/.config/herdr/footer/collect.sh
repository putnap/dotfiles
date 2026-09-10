#!/usr/bin/env bash
# One collector for the isolated server. Retain metadata and an incomplete log line.
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd -P)
source "$scripts/state-dir.sh"
herdr=${HERDR_BIN_PATH:-herdr}
mkdir -p "$root/codex"
chmod 700 "$root" "$root/codex"
socket_generation=$(stat -f '%i:%B' "${HERDR_SOCKET_PATH:?}")
# A departing server's collector must not block the next server's startup.
lock=$root/collector-$socket_generation.lock
/usr/bin/shlock -p "$$" -f "$lock" || { echo 'footer collector already running' >&2; exit 1; }
trap 'rm -f "$lock"' EXIT
umask 077
codex_sample() {
  local id=$1 dir log offset size generation
  dir=$root/codex/$id
  mkdir -p "$dir"
  if [[ ! -s $dir/path ]]; then
    [[ -d ${CODEX_HOME:-$HOME/.codex}/sessions ]] || return 1
    rg --files --hidden "${CODEX_HOME:-$HOME/.codex}/sessions" | awk -v suffix="-$id.jsonl" 'length($0) >= length(suffix) && substr($0,length($0)-length(suffix)+1)==suffix {print; exit}' > "$dir/path"
  fi
  log=$(cat "$dir/path")
  [[ -f $log ]] || return 1
  size=$(stat -f %z "$log")
  generation=$(stat -f '%i:%B' "$log")
  offset=0
  [[ ! -f $dir/offset ]] || offset=$(cat "$dir/offset")
  if [[ ! -f $dir/generation || $(cat "$dir/generation") != "$generation" || $size -lt $offset ]]; then
    offset=0
    printf '{}' > "$dir/state.json"
    : > "$dir/pending"
    printf '%s' "$generation" > "$dir/generation"
  fi
  if ((size > offset)); then
    cat "$dir/pending" > "$dir/buffer"
    tail -c +$((offset + 1)) "$log" > "$dir/chunk"
    cat "$dir/chunk" >> "$dir/buffer"
    offset=$((offset + $(wc -c < "$dir/chunk")))
    if [[ $(tail -c 1 "$dir/buffer" | od -An -tu1 | tr -d ' ') == 10 ]]; then
      cp "$dir/buffer" "$dir/complete"
      : > "$dir/pending"
    else
      sed '$d' "$dir/buffer" > "$dir/complete"
      tail -n 1 "$dir/buffer" > "$dir/pending"
    fi
    jq -Rnc --slurpfile previous "$dir/state.json" -f "$scripts/collect.jq" < "$dir/complete" > "$dir/next"
    mv "$dir/next" "$dir/state.json"
    printf '%s' "$offset" > "$dir/offset"
    rm -f "$dir/chunk" "$dir/buffer" "$dir/complete"
  fi
  jq -c -f "$scripts/codex-metrics.jq" "$dir/state.json"
}
publish() {
  local agent=$1 provider id pane terminal sample cwd branch worktree access model model_name effort current args key value initial=false process pid dir flag config_args
  provider=$(jq -r '.agent' <<< "$agent")
  id=$(jq -r '.agent_session | select(.kind == "id") | .value | select(test("^[a-zA-Z0-9_-]+$"))' <<< "$agent")
  pane=$(jq -r '.pane_id' <<< "$agent")
  terminal=$(jq -r '.terminal_id' <<< "$agent")
  cwd=$(jq -r '.foreground_cwd // .cwd' <<< "$agent")
  if [[ -z $id && $provider == codex ]]; then
    initial=true
    process=$("$herdr" pane process-info --pane "$pane" | jq -ce '.result.process_info.foreground_processes[] | select((.argv[0] | split("/") | last) == "codex")') || return 0
    pid=$(jq -r '.pid' <<< "$process")
    dir=$root/codex/start-$terminal-$pid
    mkdir -p "$dir"
    if [[ ! -f $dir/start-data.json ]]; then
      # Preserve explicit config/model/permission overrides in the read-only query.
      config_args=()
      while IFS= read -r flag; do config_args+=("$flag"); done < <(jq -r '
        .argv as $a | range(1; $a|length) as $i |
        if ($a[$i] == "-c" or $a[$i] == "--config") then "-c", $a[$i+1]
        elif ($a[$i] == "-m" or $a[$i] == "--model") then "-c", ("model=" + ($a[$i+1]|tojson))
        elif ($a[$i] == "-s" or $a[$i] == "--sandbox") then "-c", ("sandbox_mode=" + ($a[$i+1]|tojson))
        elif ($a[$i] == "-a" or $a[$i] == "--ask-for-approval") then "-c", ("approval_policy=" + ($a[$i+1]|tojson))
        elif ($a[$i] == "--dangerously-bypass-approvals-and-sandbox" or $a[$i] == "--yolo") then "-c", "sandbox_mode=\"danger-full-access\"", "-c", "approval_policy=\"never\""
        else empty end' <<< "$process")
      (cd "$cwd" && bash "$scripts/codex-start-data.sh" "$dir" "${config_args[@]}") || return 0
    fi
    sample=$(cat "$dir/start-data.json")
  else
    [[ -n $id ]] || return 0
    case "$provider" in
      claude) [[ -f $root/claude/$id.json ]] || return 0; sample=$(cat "$root/claude/$id.json");;
      codex) sample=$(codex_sample "$id") || return 0;;
      *) return 0;;
    esac
  fi
  worktree=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || worktree=$cwd
  worktree=${worktree##*/}
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null) || branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null) || branch=
  access=$(jq -nr --argjson data "$sample" \
    '(if $data.permission == "bypassPermissions" or ($data.sandbox == "danger-full-access" and $data.approval == "never") then "[bypass]"
      elif $data.sandbox == "danger-full-access" then "[full access]"
      elif $data.permission == "acceptEdits" then "[auto edits]"
      elif $data.permission == "auto" then "[auto]"
      elif $data.permission == "plan" then "[plan]"
      else "" end)')
  model=$(jq -r '[.model, .effort] | map(select(type == "string" and length > 0)) | join(" ") | .[0:80]' <<< "$sample")
  model_name=$(jq -r '.model | if type == "string" then .[0:80] else "" end' <<< "$sample")
  effort=$(jq -r '.effort | if type == "string" then .[0:80] else "" end' <<< "$sample")
  # Resolve moves again and reject stale/replaced sessions immediately before publishing.
  current=$("$herdr" agent list | jq -ce --arg terminal "$terminal" --arg id "$id" --arg provider "$provider" \
    '.result.agents[] | select(.terminal_id == $terminal and .agent == $provider and (.agent_session.value // "") == $id)') || return 0
  pane=$(jq -r '.pane_id' <<< "$current")
  args=(pane report-metadata "$pane" --source user:pane-footer --ttl-ms 15000 --token "footer_session=$id" --clear-token footer_left --token "footer_access=$access" --token "footer_dir=${worktree:0:80}" --token "footer_branch=${branch:0:80}" --token "footer_model=$model" --token "footer_model_name=$model_name" --token "footer_effort=$effort")
  if $initial; then
    # Recheck process identity after the asynchronous network request.
    "$herdr" pane process-info --pane "$pane" | jq -e --argjson pid "$pid" '.result.process_info.foreground_processes | any(.pid == $pid)' >/dev/null || return 0
    args+=(--token "footer_terminal=$terminal")
  else args+=(--clear-token footer_terminal); fi
  for key in context five_hour weekly; do
    case "$key" in context) token=footer_ctx;; five_hour) token=footer_5h;; weekly) token=footer_week;; esac
    value=$(jq -r --arg key "$key" '.[$key] | select(type == "number")' <<< "$sample")
    if [[ -n $value ]]; then args+=(--token "$token=$value"); else args+=(--clear-token "$token"); fi
  done
  "$herdr" "${args[@]}"
}
while [[ -S $HERDR_SOCKET_PATH && $(stat -f '%i:%B' "$HERDR_SOCKET_PATH") == "$socket_generation" ]]; do
  if agents=$("$herdr" agent list); then
    while IFS= read -r agent; do publish "$agent" || echo 'footer sample failed; retrying' >&2; done < <(jq -c '.result.agents[] | select(.agent == "claude" or .agent == "codex")' <<< "$agents")
  fi
  [[ ${1:-} != --once ]] || break
  sleep 3
done

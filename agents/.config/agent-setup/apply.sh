#!/usr/bin/env bash
set -euo pipefail
repo= home=$HOME apply=false integrations=false rollback=
while (($#)); do
  case "$1" in
    --repo) repo=${2:?}; shift 2;;
    --home) home=${2:?}; shift 2;;
    --apply) apply=true; shift;;
    --integrations) integrations=true; shift;;
    --rollback) rollback=${2:?}; shift 2;;
    *) echo "Unknown argument: $1" >&2; exit 1;;
  esac
done
for tool in jq dasel stow; do command -v "$tool" >/dev/null || { echo "Missing $tool; apply the Nix flake first." >&2; exit 1; }; done
if [[ -n $rollback ]]; then
  while IFS= read -r entry; do
    target=$(jq -r '.path' <<< "$entry")
    [[ ! -e $target && ! -L $target ]] || rm "$target"
    mkdir -p "$(dirname "$target")"
    if jq -e 'has("symlink")' <<< "$entry" >/dev/null; then
      ln -s "$(jq -r '.symlink' <<< "$entry")" "$target"
    elif jq -e 'has("backup")' <<< "$entry" >/dev/null; then
      cp -Rp "$(jq -r '.backup' <<< "$entry")" "$target"
    fi
  done < <(jq -c 'reverse[]' "$rollback")
  echo "Restored files from $rollback"
  exit 0
fi
[[ -n $repo ]] || { echo '--repo is required' >&2; exit 1; }
repo=$(cd "$repo" && pwd -P)
home=$(cd "$home" && pwd -P)
real_home=$(cd "$HOME" && pwd -P)
[[ $integrations == false || $home == "$real_home" ]] || { echo 'Integration installation requires the real home.' >&2; exit 1; }
if [[ $apply == true && $home == "$real_home" ]]; then
  status=$(herdr status --json)
  if jq -e '.server.running and (.server.compatible == false)' <<< "$status" >/dev/null; then
    echo 'Herdr server/CLI mismatch. Finish active work and restart herdr before applying. No live settings changed.' >&2
    exit 1
  fi
fi
config=$repo/agents/.config/agent-setup
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
state=$home/.local/state/agent-setup/owned.json
backup=$home/.local/state/agent-setup/backups/$(date +%Y%m%d-%H%M%S)-$$
printf '{}\n' > "$scratch/previous"
[[ ! -f $state ]] || cp "$state" "$scratch/previous"
printf '{}\n' > "$scratch/owned"
printf '[]\n' > "$scratch/entries"
count=0
save() {
  local target=$1 entry file
  [[ $apply == true ]] || return 0
  jq -e --arg path "$target" 'any(.[]; .path == $path)' "$scratch/entries" >/dev/null && return 0
  mkdir -p "$backup"
  chmod 700 "$backup"
  if [[ -L $target ]]; then
    entry=$(jq -cn --arg path "$target" --arg link "$(readlink "$target")" '{path:$path,symlink:$link}')
  elif [[ -f $target || -d $target ]]; then
    file=$backup/$count
    cp -Rp "$target" "$file"
    entry=$(jq -cn --arg path "$target" --arg backup "$file" '{path:$path,backup:$backup}')
  elif [[ -e $target ]]; then
    echo "Refusing to replace directory: $target" >&2; exit 1
  else entry=$(jq -cn --arg path "$target" '{path:$path}'); fi
  count=$((count+1))
  jq --argjson entry "$entry" '. + [$entry]' "$scratch/entries" > "$scratch/next"
  mv "$scratch/next" "$scratch/entries"
  cp "$scratch/entries" "$backup/manifest.json"
  chmod 600 "$backup/manifest.json"
}
write() {
  local target=$1 source=$2 temporary
  if [[ -f $target ]] && cmp -s "$source" "$target"; then return 0; fi
  echo "update $target"
  save "$target"
  [[ $apply == true ]] || return 0
  mkdir -p "$(dirname "$target")"
  temporary=$(mktemp "$(dirname "$target")/.agent-setup.XXXXXX")
  cat "$source" > "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$target"
}
# settings.json only enables a marketplace plugin; Claude fetches it through its own CLI.
install_tokeneconomizer() {
  if jq -e '.plugins["tokeneconomizer@tokeneconomizer"]' "$home/.claude/plugins/installed_plugins.json" >/dev/null 2>&1; then return 0; fi
  echo "install Claude plugin tokeneconomizer"
  [[ $apply == true ]] || return 0
  jq -e '.tokeneconomizer' "$home/.claude/plugins/known_marketplaces.json" >/dev/null 2>&1 || claude plugin marketplace add microsoft/TokenEconomizer
  claude plugin install tokeneconomizer@tokeneconomizer
}
# Tool pruning only proposes, so no tool disappears unseen; dotfiles isn't worth pruning at all.
configure_tokeneconomizer() {
  local te
  te=$(jq -r '.plugins["tokeneconomizer@tokeneconomizer"][0].installPath' "$home/.claude/plugins/installed_plugins.json")/scripts/te
  [[ $apply == true ]] || return 0
  "$te" config set toolprune=propose --global >/dev/null
  "$te" config set toolprune=off --cwd "$repo" >/dev/null
}
# Tool pruning needs the tool list each Claude Code version loads, so record it again after an upgrade.
refresh_tokeneconomizer_catalog() {
  local catalog=$home/.tokeneconomizer/hosts/claude/catalog.json version te
  version=$(claude --version | cut -d ' ' -f 1)
  if [[ $(jq -r '.claude_code_version' "$catalog" 2>/dev/null) == "$version" ]]; then return 0; fi
  echo "refresh TokenEconomizer tool catalog for Claude $version"
  [[ $apply == true ]] || return 0
  te=$(jq -r '.plugins["tokeneconomizer@tokeneconomizer"][0].installPath' "$home/.claude/plugins/installed_plugins.json")/scripts/te
  "$te" --host claude toolprune refresh-catalog >/dev/null ||
    echo "TokenEconomizer catalog refresh failed; run /tokeneconomizer:toolprune refresh-catalog in Claude" >&2
}
# Prepare every merge before changing live files.
protected='["permissions","skipDangerousModePermissionPrompt","sandbox_mode","sandbox","sandbox_permissions","approval_policy","approvals_reviewer","ask_for_approval","projects"]'
for name in claude codex peon claude-keybindings claude-theme; do
  case "$name" in
    claude) relative=.claude/settings.json;;
    codex) relative=.codex/config.toml;;
    peon) relative=.claude/hooks/peon-ping/config.json;;
    claude-keybindings) relative=.claude/keybindings.json;;
    claude-theme) relative=.claude/themes/catppuccin-mocha.json;;
  esac
  dasel -i toml -o json < "$config/$name.toml" > "$scratch/wanted"
  printf '{}\n' > "$scratch/live"
  if [[ -f $home/$relative ]]; then
    if [[ $name == codex ]]; then dasel -i toml -o json < "$home/$relative" > "$scratch/live"
    else jq . "$home/$relative" > "$scratch/live"; fi
  fi
  fields=$protected
  if [[ $name == codex ]]; then fields=$(jq -c '. - ["approval_policy","approvals_reviewer","sandbox_mode"]' <<< "$fields"); fi
  jq -n --slurpfile live "$scratch/live" --slurpfile wanted "$scratch/wanted" --slurpfile previous "$scratch/previous" \
    --arg name "$name.toml" --argjson protected "$fields" -f "$config/merge.jq" > "$scratch/merged"
  if [[ $(jq -Sc . "$scratch/live") != "$(jq -Sc . "$scratch/merged")" ]]; then
    if [[ $name == codex ]]; then dasel -i json -o toml < "$scratch/merged" > "$scratch/$name"
    else cp "$scratch/merged" "$scratch/$name"; fi
  fi
  jq --arg name "$name.toml" --slurpfile wanted "$scratch/wanted" '.[$name] = $wanted[0]' "$scratch/owned" > "$scratch/next"
  mv "$scratch/next" "$scratch/owned"
done
# Native Codex hooks are a separate JSON document.
if [[ -f $home/.codex/hooks.json ]]; then
  printf '{}\n' > "$scratch/empty"
  jq -n --slurpfile live "$home/.codex/hooks.json" --slurpfile wanted "$scratch/empty" --slurpfile previous "$scratch/empty" \
    --arg name hooks --argjson protected "$protected" -f "$config/merge.jq" > "$scratch/hooks"
  if [[ $(jq -Sc . "$home/.codex/hooks.json") == "$(jq -Sc . "$scratch/hooks")" ]]; then rm "$scratch/hooks"; fi
fi
for agent in claude codex; do
  if [[ $agent == claude ]]; then
    source=$scratch/claude
    live=$home/.claude/settings.json
  else
    source=$scratch/hooks
    live=$home/.codex/hooks.json
  fi
  if [[ -f $source ]]; then cp "$source" "$scratch/hook-source"
  elif [[ -f $live ]]; then cp "$live" "$scratch/hook-source"
  else printf '{}\n' > "$scratch/hook-source"; fi
  # Replace only our hook commands; other integrations retain their ordering.
  # One pass for both files: Codex trusts a hook by its position, so ours must not swap places.
  jq --arg agent "$agent" --slurpfile workmux "$config/workmux-hooks.json" --slurpfile atuin "$config/atuin-hooks.json" '
    def ours: (.command // "") | contains("~/.config/agent-setup/workmux-hook.sh") or contains("atuin hook ");
    .hooks = ((.hooks // {}) | with_entries(.value |= map(
      .hooks |= map(select(ours | not)) |
      select(.hooks | length > 0)))) |
    reduce (($workmux[0], $atuin[0])[$agent].hooks | to_entries[]) as $event (. ;
      .hooks[$event.key] = ((.hooks[$event.key] // []) + $event.value))
  ' "$scratch/hook-source" > "$source"
done

# Reject directory conflicts before writing any merged settings.
for package in agents claude herdr workmux; do
  while IFS= read -r -d '' source; do
    target=$home/${source#"$repo/$package/"}
    if [[ -e $target && $target -ef $source ]]; then continue; fi
    if [[ -d $target && ! -L $target && ! ( -L $source && -d $source ) ]]; then
      echo "Directory conflict: $target" >&2; exit 1
    fi
  done < <(find "$repo/$package" \( -name .DS_Store -o -name __pycache__ \) -prune -o \( -type f -o -type l \) -print0)
done
[[ ! -f $scratch/claude ]] || write "$home/.claude/settings.json" "$scratch/claude"
[[ ! -f $scratch/codex ]] || write "$home/.codex/config.toml" "$scratch/codex"
[[ ! -f $scratch/peon ]] || write "$home/.claude/hooks/peon-ping/config.json" "$scratch/peon"
[[ ! -f $scratch/hooks ]] || write "$home/.codex/hooks.json" "$scratch/hooks"
[[ ! -f $scratch/claude-keybindings ]] || write "$home/.claude/keybindings.json" "$scratch/claude-keybindings"
[[ ! -f $scratch/claude-theme ]] || write "$home/.claude/themes/catppuccin-mocha.json" "$scratch/claude-theme"
for package in agents claude herdr workmux; do
  while IFS= read -r -d '' source; do
    target=$home/${source#"$repo/$package/"}
    if [[ -e $target && $target -ef $source ]]; then continue; fi
    echo "link $target -> $source"
    save "$target"
    if [[ $apply == true && ( -e $target || -L $target ) ]]; then
      if [[ -d $target && ! -L $target ]]; then
        mv "$target" "$backup/replaced-directory-$count"
      else rm "$target"; fi
    fi
  done < <(find "$repo/$package" \( -name .DS_Store -o -name __pycache__ \) -prune -o \( -type f -o -type l \) -print0)
done
if [[ $apply == true ]]; then stow --no-folding --ignore='__pycache__|\.DS_Store' --dir "$repo" --target "$home" agents claude herdr workmux; fi
if [[ $integrations == true ]]; then
  integration_status=$(herdr integration status)
  while IFS= read -r agent; do
    case "$agent" in claude|codex) ;; *) echo "Unknown integration: $agent" >&2; exit 1;; esac
    if grep -Eq "^$agent: (installed|current)( |$)" <<< "$integration_status"; then continue; fi
    echo "install herdr integration $agent"
    if [[ $apply == true ]]; then
      for relative in .claude/settings.json .claude/hooks/herdr-agent-state.sh .codex/hooks.json .codex/herdr-agent-state.sh .codex/config.toml; do save "$home/$relative"; done
      herdr integration install "$agent"
    fi
  done < <(dasel -i toml -o json < "$repo/herdr/.config/herdr/plugins/config/agents/config.toml" | jq -r '.integrations[]')
  # Claude keeps user MCP servers in ~/.claude.json, which it rewrites constantly, so add once.
  if ! jq -e '.mcpServers.atuin' "$home/.claude.json" >/dev/null 2>&1; then
    echo "add Claude MCP server atuin"
    if [[ $apply == true ]]; then
      save "$home/.claude.json"
      claude mcp add --scope user atuin -- /run/current-system/sw/bin/atuin mcp
    fi
  fi
  install_tokeneconomizer
  configure_tokeneconomizer
  refresh_tokeneconomizer_catalog
fi
registry=$home/.config/herdr/plugins.json
[[ ! -f $registry ]] || cp "$registry" "$scratch/registry"
[[ -f $scratch/registry ]] || printf '[]\n' > "$scratch/registry"
for plugin in "$repo"/herdr/.config/herdr/local-plugins/*; do
  [[ -f $plugin/herdr-plugin.toml ]] || continue
  id=$(dasel -i toml -o json < "$plugin/herdr-plugin.toml" | jq -er '.id')
  digest=$(shasum -a 256 "$plugin/herdr-plugin.toml" | cut -d ' ' -f 1)
  jq --arg id "$id" --arg digest "$digest" '._plugins[$id] = $digest' "$scratch/owned" > "$scratch/next"
  mv "$scratch/next" "$scratch/owned"
  if jq -e --arg id "$id" --arg root "$plugin" 'any(.[]; .plugin_id == $id and .plugin_root == $root and .enabled)' "$scratch/registry" >/dev/null &&
     jq -e --arg id "$id" --arg digest "$digest" '._plugins[$id] == $digest' "$scratch/previous" >/dev/null; then continue; fi
  echo "register herdr plugin $id"
  if [[ $apply == true && $home == "$real_home" ]]; then save "$registry"; herdr plugin link "$plugin"; fi
done
# GitHub plugins clone and build over the network, so they install with the integrations.
if [[ $integrations == true ]]; then
  while IFS= read -r source; do
    if jq -e --arg source "$source" 'any(.[]; .source.kind == "github" and "\(.source.owner)/\(.source.repo)" == $source)' "$scratch/registry" >/dev/null; then continue; fi
    echo "install herdr plugin $source"
    if [[ $apply == true ]]; then save "$registry"; herdr plugin install "$source" --yes; fi
  done < <(dasel -i toml -o json < "$repo/herdr/.config/herdr/plugins/config/agents/config.toml" | jq -r '.plugins[]')
fi
write "$state" "$scratch/owned"
if [[ $apply == true && $home == "$real_home" ]] && herdr status --json | jq -e '.server.running' >/dev/null; then
  herdr server reload-config
fi
[[ $count == 0 ]] || echo "Rollback manifest: $backup/manifest.json"
if [[ $apply == true ]]; then echo 'Applied.'; else echo 'Dry run only. Use --apply to write.'; fi

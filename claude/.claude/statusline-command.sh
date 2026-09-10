#!/usr/bin/env bash
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model=$(echo "$input" | jq -r '.model.display_name // ""')
effort=$(echo "$input" | jq -r '.effort.level // ""')
remaining=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# Git info (skip optional locks)
git_info=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" -c core.fsync=none symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | grep -q . && echo "*" || echo "")
  ahead=$(git -C "$cwd" rev-list @{u}..HEAD 2>/dev/null | wc -l | tr -d ' ')
  behind=$(git -C "$cwd" rev-list HEAD..@{u} 2>/dev/null | wc -l | tr -d ' ')
  arrows=""
  [ "$behind" -gt 0 ] 2>/dev/null && arrows="${arrows}⇣"
  [ "$ahead" -gt 0 ] 2>/dev/null && arrows="${arrows}⇡"
  git_info=" ${branch}${dirty}${arrows:+ $arrows}"
fi

# Context usage
ctx=""
if [ -n "$remaining" ]; then
  ctx=" | ${remaining}%"
fi

# Colors: green path, grey git, default model+ctx
printf '\033[32m%s\033[0m\033[2m%s\033[0m%s%s' "$cwd" "$git_info" " | ${model:+$model} - (${effort})" "$ctx"

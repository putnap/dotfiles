#!/bin/sh
# Focused workspace name for the tab bar. Worktree children show repo/branch,
# since their own label is only the branch slug.
herdr workspace list | jq -r '
  .result.workspaces[]
  | select(.focused)
  | if .worktree.is_linked_worktree
    then "\(.worktree.repo_name)/\(.label)"
    else .label
    end'

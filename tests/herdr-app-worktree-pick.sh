#!/usr/bin/env bash
# herdr-app's ctrl+\ ctrl+g picker (mods/git-worktree/pick.sh) on a real repo: it lists the
# worktrees, main first, then the branches none holds (remote-only ones stripped of origin/);
# a worktree with a space selects it, one without gets a new space; a branch, a remote-only
# branch and a new name each get a worktree beside the repo and a space running paseo.json's
# setup. fzf, herdr-app and hc are stubs that answer from files and log what they were asked.
set -euo pipefail
dotfiles=$(cd "$(dirname "$0")/.." && pwd -P)
pick=$dotfiles/herdr-app/.config/herdr-app/mods/git-worktree/pick.sh
scratch=$(mktemp -d /tmp/herdr-app-pick.XXXXXX)
# Resolved, because git reports /tmp checkouts by their real /private/tmp path.
scratch=$(cd "$scratch" && pwd -P)
trap 'rm -rf "$scratch"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

make_stubs() {
  mkdir -p "$scratch/bin"
  # fzf: keeps the rows it was given; answers the query, and the row whose value is $PICK.
  cat > "$scratch/bin/fzf" <<'STUB'
#!/usr/bin/env bash
cat > "$SCRATCH/rows"
printf '%s\n' "${QUERY:-}"
row=$(awk -F'\t' -v v="${PICK:-}" 'v != "" && $2 == v' "$SCRATCH/rows")
[ -n "$row" ] || exit 1
printf '%s\n' "$row"
STUB
  cat > "$scratch/bin/herdr-app" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = ls ]; then cat "$SCRATCH/spaces.json"; else printf '%s\n' "$*" >> "$SCRATCH/do.log"; fi
STUB
  cat > "$scratch/bin/hc" <<'STUB'
#!/usr/bin/env bash
cat "$SCRATCH/terminals.json"
STUB
  chmod +x "$scratch/bin/"*
}

make_repo() {
  git init -q -b main "$scratch/origin"
  git -C "$scratch/origin" -c user.name=t -c user.email=t@e commit -q --allow-empty -m init
  git -C "$scratch/origin" branch feature/remote-only
  git clone -q "$scratch/origin" "$scratch/app"
  git -C "$scratch/app" branch feature/local
  git -C "$scratch/app" branch feature/held
  git -C "$scratch/app" worktree add -q "$scratch/app-held" feature/held
  jq -n '{worktree: {setup: "echo setup"}}' > "$scratch/app/paseo.json"
}

# One space on the held worktree (its terminal moved there from where the space was made).
make_spaces() {
  jq -n --arg app "$scratch/app" '{spaces: [{id: "sp1", folder: $app, machine: null, tabs: [{terminals: [{terminal: "t1"}]}]}]}' > "$scratch/spaces.json"
  jq -n --arg held "$scratch/app-held" '{terminals: [{address: "t1", cwd: $held}]}' > "$scratch/terminals.json"
}

run_pick() {
  : > "$scratch/do.log"
  (cd "$scratch/app" && QUERY=$1 PICK=$2 PATH=$scratch/bin:$PATH bash "$pick" </dev/null >/dev/null 2>&1) || fail "pick.sh exited $? for query '$1' pick '$2'"
}

expect_rows() {
  local values
  values=$(cut -f1,2 "$scratch/rows" | tr '\t' ' ')
  [ "$values" = "worktree $scratch/app
worktree $scratch/app-held
branch feature/local
branch feature/remote-only" ] || fail "rows were: $values"
}

expect_do() {
  grep -qxF -- "$1" "$scratch/do.log" || fail "expected herdr-app $1, got: $(cat "$scratch/do.log")"
}

expect_branch_at() {
  [ "$(git -C "$2" branch --show-current)" = "$1" ] || fail "$2 is not on $1"
}

new_space_args() {
  jq -nc --arg folder "$1" '{folder: $folder, argv: ["/bin/sh", "-c", "exec \"${SHELL:-/bin/zsh}\" -lic \"$1\"", "sh", "echo setup; exec \"$SHELL\" -l"]}'
}

export SCRATCH=$scratch
make_stubs
make_repo
make_spaces

run_pick "" "$scratch/app-held"
expect_rows
expect_do "do space.select --id sp1"

run_pick "" "$scratch/app"
expect_do "do space.new --folder $scratch/app"

run_pick "" feature/local
expect_branch_at feature/local "$scratch/app-local"
expect_do "do space.new $(new_space_args "$scratch/app-local")"

run_pick "" feature/remote-only
expect_branch_at feature/remote-only "$scratch/app-remote-only"
[ "$(git -C "$scratch/app" rev-parse --abbrev-ref feature/remote-only@{upstream})" = origin/feature/remote-only ] ||
  fail "feature/remote-only does not track origin"

run_pick fix/brand-new ""
expect_branch_at fix/brand-new "$scratch/app-brand-new"
expect_do "do space.new $(new_space_args "$scratch/app-brand-new")"

echo "ok herdr-app worktree picker"

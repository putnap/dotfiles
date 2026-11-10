#!/usr/bin/env bash
# herdr-app's ctrl+? list (mods/keys/help.sh): fzf shows the rows' second column; the chosen
# row's action lands in the choice file, and esc leaves it empty, even after an earlier choice.
# fzf is a stub that keeps what it was given and answers the row whose action is $PICK.
set -euo pipefail
dotfiles=$(cd "$(dirname "$0")/.." && pwd -P)
help=$dotfiles/herdr-app/.config/herdr-app/mods/keys/help.sh
scratch=$(mktemp -d /tmp/herdr-app-keys-help.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$scratch/bin"
cat >"$scratch/bin/fzf" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$SCRATCH/args"
cat >"$SCRATCH/rows"
row=$(awk -F'\t' -v v="${PICK:-}" 'v != "" && $1 == v' "$SCRATCH/rows")
[ -n "$row" ] || exit 130
printf '%s\n' "$row"
STUB
chmod +x "$scratch/bin/fzf"
export PATH="$scratch/bin:$PATH" SCRATCH=$scratch

rows=$'keys.press:z\tprefix z                 zoom      Panes\ntab.select:1\tcmd+1                    tab select 1   global'
choice=$scratch/choice

PICK=tab.select:1 bash "$help" "$rows" "$choice"
[ "$(cat "$choice")" = tab.select:1 ] || fail "the chosen action is not in the choice file: $(cat "$choice")"
grep -q -- '--with-nth=2' "$scratch/args" || fail "fzf shows more than the shown column"
[ "$(wc -l <"$scratch/rows" | tr -d ' ')" = 2 ] || fail "fzf did not get every row"

PICK= bash "$help" "$rows" "$choice"
[ ! -s "$choice" ] || fail "esc left the earlier choice: $(cat "$choice")"

echo "PASS herdr-app keys help"

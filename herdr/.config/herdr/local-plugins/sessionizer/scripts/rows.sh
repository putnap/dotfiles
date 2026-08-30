#!/usr/bin/env bash
# Full picker row set, used for every live refresh: open workspaces re-queried,
# repo list served from the cache picker.sh built once at startup.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash "$here/open-rows.sh"
cat "${1:?usage: rows.sh <repo-cache>}"

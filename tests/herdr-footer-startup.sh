#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"
cat > "$tmp/bin/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $* == 'app-server --listen stdio:// -c model="test-model"' ]] || exit 9
while IFS= read -r line; do
  case $(jq -r '.id // empty' <<< "$line") in
    1) printf '%s\n' '{"id":1,"result":{}}';;
    2) printf '%s\n' '{"id":2,"result":{"config":{"model":"test-model","model_reasoning_effort":"high","approval_policy":"never","sandbox_mode":"danger-full-access"}}}';;
    3) printf '%s\n' '{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":23,"windowDurationMins":10080},"secondary":null}}}';;
  esac
done
SH
chmod +x "$tmp/bin/codex"
PATH="$tmp/bin:$PATH" bash "$repo/herdr/.config/herdr/footer/codex-start-data.sh" "$tmp/state" -c 'model="test-model"'
jq -e '.model == "test-model" and .effort == "high" and .approval == "never" and .sandbox == "danger-full-access" and .weekly == 23 and .five_hour == null and (has("context")|not)' "$tmp/state/start-data.json" >/dev/null
printf '%s\n' 'startup metadata fixtures passed'
if [[ ${1:-} == --native ]]; then
  python3 -u - "${CODEX_BIN:-codex}" <<'PY'
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import sys
import tempfile
import termios
import time

binary = shutil.which(sys.argv[1]) or sys.argv[1]
with tempfile.TemporaryDirectory(prefix="codex-footer-native-") as directory:
    root = Path(directory).resolve()
    directory = str(root)
    for name in ("models_cache.json",):
        source = Path.home() / ".codex" / name
        if source.exists():
            (root / name).symlink_to(source)
    (root / "config.toml").write_text('model="gpt-6-astra"\nmodel_provider="footer_test"\ncheck_for_update_on_startup=false\n'
        'approval_policy="never"\nsandbox_mode="danger-full-access"\n'
        '[tui]\nstatus_line=[]\n[features]\nhooks=false\n'
        '[model_providers.footer_test]\nname="Footer test"\nbase_url="http://127.0.0.1:1/v1"\n'
        'env_key="CODEX_FOOTER_TEST_KEY"\nwire_api="responses"\n'
        f'[projects.{json.dumps(directory)}]\ntrust_level="trusted"\n')
    env = dict(os.environ, CODEX_HOME=directory, HERDR_SOCKET_PATH=str(root / "test.sock"),
               HERDR_PANE_ID="w1:p1", TERM="xterm-256color", COLORTERM="truecolor", CODEX_FOOTER_TEST_KEY="test")
    env.pop("NO_COLOR", None)
    env.pop("CODEX_THREAD_ID", None)
    pid, terminal = pty.fork()
    if pid == 0:
        os.chdir(directory)
        os.execvpe(binary, [binary, "--no-alt-screen"], env)
    fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 140, 0, 0))
    output = bytearray()
    sample_path = root / "herdr" / f"{pid}.json"

    def wait_for(predicate, timeout=60):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if select.select([terminal], [], [], 0.05)[0]:
                try:
                    data = os.read(terminal, 65536)
                except OSError:
                    break
                output.extend(data)
                if b"\x1b[?u" in data:
                    os.write(terminal, b"\x1b[?1u")
                if b"\x1b[6n" in data:
                    os.write(terminal, b"\x1b[1;1R")
            sample = json.loads(sample_path.read_text()) if sample_path.exists() else {}
            if predicate(sample):
                return sample
        raise AssertionError("native footer condition not reached: " + output[-2500:].decode(errors="replace"))

    def type_command(command):
        # Bracketed paste keeps the command intact and separate from its submit key.
        os.write(terminal, b"\x15\x1b[200~" + command.encode() + b"\x1b[201~")
        time.sleep(0.2)
        os.write(terminal, b"\r")

    try:
        first = wait_for(lambda s: s.get("session_id") is not None)
        print("Native session initialized")
        assert first["approval"] == "never" and first["context"] == 0, first
        wait_for(lambda s: b"48;2;57;57;71" in output)
        assert b"? for shortcuts" in output, "keypress hints disappeared"
        assert b"context left" not in output, "duplicate context indicator remains"
        type_command("/permissions")
        wait_for(lambda s: b"Update Model Permissions" in output)
        os.write(terminal, b"\x1b[H")
        time.sleep(0.2)
        os.write(terminal, b"\r")
        changed = wait_for(lambda s: s.get("approval") == "on-request")
        print("Native permissions changed without a turn")
        assert changed["session_id"] == first["session_id"], changed
        type_command("/new")
        fresh = wait_for(lambda s: s.get("session_id") not in (None, first["session_id"]))
        assert fresh["context"] == 0, fresh
        for log in (root / "sessions").rglob("*.jsonl"):
            for line in log.read_text().splitlines():
                row = json.loads(line)
                assert not (row.get("type") == "event_msg" and row.get("payload", {}).get("type") in
                            ("user_message", "task_started")), "a test unexpectedly submitted a model prompt"
        print("Native Codex passed: idle permission change, new session, input background, keypress hints; no model prompt.")
    finally:
        os.write(terminal, b"\x04")
        deadline = time.monotonic() + 5
        while os.waitpid(pid, os.WNOHANG) == (0, 0):
            if time.monotonic() >= deadline:
                os.kill(pid, signal.SIGKILL)
                break
            if select.select([terminal], [], [], 0.05)[0]:
                try:
                    os.read(terminal, 65536)
                except OSError:
                    pass
            time.sleep(0.05)
        os.close(terminal)
PY
fi

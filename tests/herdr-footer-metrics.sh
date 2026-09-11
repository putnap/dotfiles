#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scripts=$repo/herdr/.config/herdr/footer
sample='{"info":{"model_context_window":258400,"last_token_usage":{"total_tokens":15634}},"rate_limits":{"primary":{"window_minutes":10080,"used_percent":22}}}'
jq -c -f "$scripts/codex-metrics.jq" <<< "$sample" | jq -e '.context == 1 and .five_hour == null and .weekly == 22' >/dev/null
jq -c -f "$scripts/codex-metrics.jq" <<< '{}' | jq -e '.context == null and .five_hour == null and .weekly == null' >/dev/null
printf '%s\n' '{"type":"turn_context","payload":{"model":"test","effort":"high","approval_policy":"never","sandbox_policy":{"type":"danger-full-access"}}}' '{"type":"response_item","payload":{"text":"must not remain"}}' 'invalid' |
  jq -Rnc --argjson previous '[{}]' -f "$scripts/collect.jq" |
  jq -e '. == {model:"test",effort:"high",cwd:null,approval:"never",sandbox:"danger-full-access"}' >/dev/null
printf '%s\n' 'metric fixtures passed'
# Exercise the running collector through its socket protocol and native metadata files.
python3 - "$repo" <<'PY'
import fcntl
import json
import os
from pathlib import Path
import socketserver
import subprocess
import sys
import tempfile
import threading
import time

repo = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix="herdr-footer-test-") as directory:
    root = Path(directory)
    socket_path = str(root / "herdr.sock")
    native = root / "codex/herdr" / f"{os.getpid()}.json"
    native.parent.mkdir(parents=True)
    # A stub app-server, so the account usage refresh is exercised without the network.
    (root / "bin").mkdir()
    stub = root / "bin/codex"
    stub.write_text("""#!/usr/bin/env bash
set -euo pipefail
[[ $1 == app-server ]] || exit 9
while IFS= read -r line; do
  case $(jq -r '.id // empty' <<< "$line") in
    1) printf '%s\\n' '{"id":1,"result":{}}';;
    2) printf '%s\\n' '{"id":2,"result":{"config":{"model":"stub","model_reasoning_effort":"low","approval_policy":"never","sandbox_mode":"read-only"}}}';;
    3) printf '%s\\n' '{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":88,"windowDurationMins":10080,"resetsAt":RESET},"secondary":{"usedPercent":4,"windowDurationMins":300,"resetsAt":RESET}}}}';;
  esac
done
""".replace("RESET", str(int(time.time() + 3600))))
    stub.chmod(0o755)
    (root / "state/claude").mkdir(parents=True)
    later = time.time() + 3600

    def claude_sample(name, **fields):
        (root / f"state/claude/{name}.json").write_text(json.dumps(fields))

    claude_sample("claude-session", model="Claude", context=41, permission="auto", measured_at=time.time(),
                  five_hour=7, weekly=61, five_hour_resets_at=later, weekly_resets_at=later)
    claude_sample("idle-session", model="Claude", context=12, permission="default", measured_at=time.time() - 36000,
                  five_hour=1, weekly=52, five_hour_resets_at=later, weekly_resets_at=later)
    agents = [
        {"agent": "codex", "terminal_id": "codex-terminal", "pane_id": "w1:p1", "cwd": directory,
         "agent_session": {"value": "old-session", "kind": "id"}},
        {"agent": "claude", "terminal_id": "claude-terminal", "pane_id": "w1:p2", "cwd": directory,
         "agent_session": {"value": "claude-session", "kind": "id"}},
        {"agent": "claude", "terminal_id": "idle-terminal", "pane_id": "w1:p4", "cwd": directory,
         "agent_session": {"value": "idle-session", "kind": "id"}},
        # A terminal still being restored reports no agent yet.
        {"terminal_id": "restoring-terminal", "pane_id": "w1:p3", "cwd": directory},
    ]
    published = {}
    claude_published = threading.Event()
    broken = threading.Event()
    replaced = False
    process_reads = 0

    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            global process_reads
            request = json.loads(self.rfile.readline())
            method, params = request["method"], request["params"]
            if method == "agent.list":
                result = {} if broken.is_set() else {"agents": agents}
            elif method == "pane.process_info":
                # A blocked Codex lookup must not prevent Claude from publishing.
                if not claude_published.wait(5):
                    raise AssertionError("Codex lookup blocked Claude publication")
                process_reads += 1
                result = {"process_info": {"foreground_processes": [{"pid": os.getpid() + int(replaced and process_reads > 1), "argv": ["codex"]}]}}
            elif method == "pane.report_metadata":
                published[params["pane_id"]] = params["tokens"]
                if params["pane_id"] == "w1:p2":
                    claude_published.set()
                result = {}
            else:
                raise AssertionError(method)
            self.wfile.write(json.dumps({"id": request["id"], "result": result}).encode() + b"\n")

    server = socketserver.ThreadingUnixStreamServer(socket_path, Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    environment = dict(os.environ, HERDR_SOCKET_PATH=socket_path, HERDR_FOOTER_STATE_DIR=str(root / "state"),
                       CODEX_HOME=str(root / "codex"), LC_ALL="C",
                       PATH=f'{root / "bin"}{os.pathsep}{os.environ["PATH"]}')

    def collect(sample):
        global process_reads
        process_reads = 0
        published.clear()
        claude_published.clear()
        native.write_text(json.dumps(dict(sample, pid=os.getpid(), socket=socket_path)))
        subprocess.run(["bash", str(repo / "herdr/.config/herdr/footer/collect.sh"), "--once"],
                       env=environment, check=True, timeout=10)
        return published.get("w1:p1")

    sample = {"session_id": "old-session", "model": "Codex", "effort": "medium", "context": 32,
              "permission_label": "Workspace", "approval": "on-request", "sandbox": {"type": "workspace-write"}}
    abandoned = root / "state/collector-1-1.lock"
    abandoned.write_text("1")
    retained = root / "state/collector-2-2.lock"
    holder = retained.open("a+")
    fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)
    first = collect(sample)
    assert not abandoned.exists(), "an unheld lock from a retired generation was kept"
    assert retained.exists(), "a lock another collector still holds was removed"
    assert first["footer_ctx"] == "32" and first["footer_access"] == "[workspace]", first
    assert published["w1:p2"]["footer_ctx"] == "41"
    # Usage belongs to the account, so the idle pane reports the newest reading, not its own.
    assert published["w1:p4"]["footer_ctx"] == "12", published["w1:p4"]
    for pane in ("w1:p2", "w1:p4"):
        assert published[pane]["footer_5h"] == "7" and published[pane]["footer_week"] == "61", published[pane]
    # A window that already rolled over is dropped rather than reported as current.
    earlier = time.time() - 60
    claude_sample("claude-session", model="Claude", context=41, permission="auto", measured_at=time.time(),
                  five_hour=7, weekly=61, five_hour_resets_at=later, weekly_resets_at=earlier)
    claude_sample("idle-session", model="Claude", context=12, permission="default", measured_at=time.time() - 36000,
                  five_hour=1, weekly=52, five_hour_resets_at=later, weekly_resets_at=earlier)
    collect(sample)
    assert published["w1:p2"]["footer_5h"] == "7", published["w1:p2"]
    assert published["w1:p2"]["footer_week"] is None, published["w1:p2"]
    claude_sample("claude-session", model="Claude", context=41, permission="auto", measured_at=time.time(),
                  five_hour=7, weekly=61, five_hour_resets_at=later, weekly_resets_at=later)
    claude_sample("idle-session", model="Claude", context=12, permission="default", measured_at=time.time() - 36000,
                  five_hour=1, weekly=52, five_hour_resets_at=later, weekly_resets_at=later)
    # No rollout or new registry entry exists yet, but the TUI has changed permissions and cleared.
    fresh = collect(dict(sample, session_id="new-session", context=0, approval="never",
                         permission_label="Full Access", sandbox={"type": "danger-full-access"}))
    assert fresh["footer_ctx"] == "0" and fresh["footer_access"] == "[bypass]", fresh
    assert fresh["footer_5h"] is None and fresh["footer_week"] is None
    unknown = collect(dict(sample, context=None))
    assert unknown["footer_ctx"] is None, unknown
    replaced = True
    assert collect(sample) is None, "a replaced process received stale metadata"
    replaced = False
    process_reads = 0
    published.clear()
    collector = subprocess.Popen(["bash", str(repo / "herdr/.config/herdr/footer/collect.sh")], env=environment)
    try:
        deadline = time.monotonic() + 5
        while "w1:p1" not in published and time.monotonic() < deadline:
            time.sleep(0.01)
        assert published["w1:p1"]["footer_ctx"] == "32"
        update = dict(sample, pid=os.getpid(), socket=socket_path, session_id="fresh-session",
                      context=0, approval="never", sandbox={"type": "danger-full-access"})
        temporary = native.with_suffix(".tmp")
        temporary.write_text(json.dumps(update))
        started = time.monotonic()
        temporary.replace(native)
        while published["w1:p1"]["footer_ctx"] != "0" and time.monotonic() - started < 2:
            time.sleep(0.01)
        elapsed = time.monotonic() - started
        assert published["w1:p1"]["footer_ctx"] == "0", "running collector kept stale context"
        assert published["w1:p1"]["footer_access"] == "[bypass]"
        print(f"Running collector refreshed permission and context in {elapsed:.3f}s")
        # Codex usage is read from the account, so a pane reports it without logging a turn.
        deadline = time.monotonic() + 20
        while published["w1:p1"].get("footer_week") != "88" and time.monotonic() < deadline:
            time.sleep(0.05)
        assert published["w1:p1"]["footer_week"] == "88", published["w1:p1"]
        assert published["w1:p1"]["footer_5h"] == "4", published["w1:p1"]
        # A second collector must not sample the same socket generation.
        duplicate = subprocess.run(["bash", str(repo / "herdr/.config/herdr/footer/collect.sh"), "--once"],
                                   env=environment, capture_output=True, text=True, timeout=10)
        assert duplicate.returncode != 0 and "already running" in duplicate.stderr, duplicate
        # An unusable snapshot must not end footer updates for the rest of the session.
        broken.set()
        time.sleep(0.6)
        broken.clear()
        published.clear()
        deadline = time.monotonic() + 10
        while "w1:p1" not in published and time.monotonic() < deadline:
            time.sleep(0.01)
        assert "w1:p1" in published, "collector did not recover from an unusable snapshot"
        assert collector.poll() is None, "collector exited on an unusable snapshot"
    finally:
        collector.terminate()
        collector.wait(timeout=5)
    server.shutdown()
    server.server_close()
print("Collector integration passed: independent panes, idle permission updates, fresh session context,\n unknown values cleared, single instance per socket, abandoned locks swept,\n account usage shared across panes and refreshed for Codex,\n recovery from an unusable snapshot.")
PY

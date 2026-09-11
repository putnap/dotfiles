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
    (root / "state/claude").mkdir(parents=True)
    (root / "state/claude/claude-session.json").write_text(json.dumps({"model": "Claude", "context": 41, "permission": "auto"}))
    agents = [
        {"agent": "codex", "terminal_id": "codex-terminal", "pane_id": "w1:p1", "cwd": directory,
         "agent_session": {"value": "old-session", "kind": "id"}},
        {"agent": "claude", "terminal_id": "claude-terminal", "pane_id": "w1:p2", "cwd": directory,
         "agent_session": {"value": "claude-session", "kind": "id"}},
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
                       CODEX_HOME=str(root / "codex"), LC_ALL="C")

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
print("Collector integration passed: independent panes, idle permission updates, fresh session context,\n unknown values cleared, single instance per socket, abandoned locks swept,\n recovery from an unusable snapshot.")
PY

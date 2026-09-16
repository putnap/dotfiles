#!/usr/bin/env bash
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd -P)
source "$scripts/state-dir.sh"
exec python3 - "$scripts" "$root" "$@" <<'PY'
import datetime
import fcntl
import json
import logging
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import threading
import time
import tomllib
import unicodedata

scripts, root = map(Path, sys.argv[1:3])
tmux_backend = "--tmux" in sys.argv[3:]
socket_path = os.environ["TMUX"].split(",")[0] if tmux_backend else os.environ["HERDR_SOCKET_PATH"]
codex_home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
root.mkdir(parents=True, exist_ok=True, mode=0o700)
os.umask(0o077)
logging.basicConfig(format="%(asctime)s %(levelname)s %(message)s")
INTERVAL = 0.25
BACKOFF_LIMIT = 5.0
QUOTA_INTERVAL = 120.0
QUOTA_FIELDS = ("five_hour", "weekly", "five_hour_resets_at", "weekly_resets_at", "has_credits")
MODE_RECORD = re.compile(rb'^\{.*"permissionMode".*$', re.M)


def socket_generation():
    # An inode alone can be reused, letting a departing collector hold the next server's lock.
    info = os.stat(socket_path)
    return f"{info.st_ino}-{int(info.st_birthtime)}"


generation = socket_generation()
lock_path = root / f"collector-{generation}.lock"
lock = lock_path.open("a+")
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit("footer collector already running")
lock.seek(0)
lock.truncate()
lock.write(str(os.getpid()))
lock.flush()
for stale in root.glob("collector-*.lock"):
    # A retired generation can never gain a collector, so an unheld lock is only litter.
    if stale != lock_path:
        try:
            with stale.open("a+") as holder:
                fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)
                stale.unlink()
        except (BlockingIOError, FileNotFoundError):
            pass
stop = threading.Event()
agents = {}
workers = {}
quotas = {}
state_lock = threading.Lock()
quota_lock = threading.Lock()
once = "--once" in sys.argv[3:]


class RpcError(RuntimeError):
    """The server refused a request, which is expected whenever a pane or agent disappears."""


def interval(failures):
    # A departing server or a wedged pane must not keep sampling at the full rate.
    return min(INTERVAL * 2 ** failures, BACKOFF_LIMIT)


def report(event, **context):
    error = sys.exc_info()[1]
    fields = " ".join(f"{key}={value}" for key, value in context.items())
    # A refusal is ordinary pane churn; a traceback belongs to a real bug.
    if isinstance(error, RpcError):
        logging.warning("%s %s error=%r", event, fields, str(error))
    else:
        logging.exception("%s %s", event, fields)


def rpc(method, params=None):
    if tmux_backend:
        return tmux_rpc(method, params or {})
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(2)
        connection.connect(socket_path)
        request = {"id": "footer", "method": method, "params": params or {}}
        connection.sendall(json.dumps(request).encode() + b"\n")
        with connection.makefile("rb") as response:
            value = json.loads(response.readline())
        if "error" in value:
            raise RpcError(value["error"])
        return value["result"]


def read_json(path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return None


def identity(agent):
    return agent["agent"], (agent.get("agent_session") or {}).get("value", "")


def observed_at(value):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return None
    return None


def share_quota(provider, sample):
    """Record this observation of the account's usage and answer with the freshest one."""
    reading = {field: sample.get(field) for field in QUOTA_FIELDS}
    measured = observed_at(sample.get("measured_at"))
    usable = measured is not None and any(reading[field] is not None for field in ("five_hour", "weekly"))
    with quota_lock:
        known = quotas.get(provider)
        if usable and (known is None or measured >= known["measured_at"]):
            quotas[provider] = dict(reading, measured_at=measured)
        return dict(quotas.get(provider) or {})


def compact(value):
    # A raw token count is unreadable at a glance and not worth the width.
    for limit, suffix in ((1_000_000_000, "B"), (1_000_000, "M"), (1_000, "k")):
        if value >= limit:
            return f"{value / limit:.1f}{suffix}".replace(".0", "")
    return str(int(value))


def quota_value(quota, key):
    # A window that has already rolled over says nothing about the one now running.
    resets_at = quota.get(f"{key}_resets_at")
    if isinstance(resets_at, (int, float)) and resets_at <= time.time():
        return None
    return quota.get(key)


def command(*args, cwd=None, input=None):
    return subprocess.check_output(args, cwd=cwd, input=input, text=True, stderr=subprocess.DEVNULL)


def tmux(*args):
    return command("tmux", "-S", socket_path, *args)


def tmux_rpc(method, params):
    if method == "agent.list":
        rows = tmux("list-panes", "-a", "-F",
                    '#{pane_id}\t#{pane_pid} #{pane_current_command}\t#{pane_current_path}\t#{@workmux_hook}').splitlines()
        result = []
        for row in rows:
            pane_id, live_identity, cwd, stored = row.split("\t", 3)
            record = json.loads(stored) if stored else {}
            if record.get("identity") != live_identity:
                if tmux("show-options", "-pqv", "-t", pane_id, "@footer").strip():
                    tmux("set-option", "-pu", "-t", pane_id, "@footer")
                continue
            result.append({"pane_id": pane_id, "terminal_id": pane_id + ":" + live_identity,
                           "cwd": cwd, "agent": record["provider"],
                           "agent_session": {"value": record["session"]}})
        return {"agents": result}
    if method == "pane.process_info":
        tty = tmux("display-message", "-p", "-t", params["pane_id"], "#{pane_tty}").strip()
        processes = []
        for line in command("ps", "-t", tty, "-o", "pid=,comm=").splitlines():
            pid, executable = line.strip().split(None, 1)
            if Path(executable).name in ("codex", ".codex-wrapped"):
                processes.append({"pid": int(pid), "argv": [executable]})
        return {"process_info": {"foreground_processes": processes}}
    if method == "pane.report_metadata":
        pane_id = params["pane_id"]
        width = int(tmux("display-message", "-p", "-t", pane_id, "#{pane_width}").strip())
        with (scripts.parent / "pane-footer.toml").open("rb") as file:
            config = tomllib.load(file)
        tmux("set-option", "-p", "-t", pane_id, "@footer", render_footer(params["tokens"], config, width))
        return {}
    raise RpcError(f"unsupported tmux footer operation: {method}")


def render_footer(tokens, config, width):
    if not config.get("enabled", True):
        return ""
    options = dict(line.split(" ", 1) for line in tmux("show-options", "-g").splitlines() if " " in line)
    palette = {}
    for name in ("red", "green", "yellow", "blue", "mauve", "teal", "peach", "text", "subtext0", "surface0"):
        option = {"text": "fg", "subtext0": "subtext_0", "surface0": "surface_0"}.get(name, name)
        palette[name] = options.get("@thm_" + option, "default").strip('"')
    names = dict(access="access", mode="mode", directory="dir", branch="branch", model="model_name",
                 effort="effort", context="ctx", tokens="tokens", five_hour="5h", weekly="week", credits="credits")

    def color(name):
        return palette.get(name, name)

    def clean(value):
        # Treat session metadata as text, never as tmux format or style directives.
        return "".join(c for c in str(value) if not unicodedata.category(c).startswith("C")).replace("#", "＃")

    def field(name):
        value = tokens.get("footer_" + names[name])
        if value is None or value == "":
            return []
        tint = config.get(name + "_color", "text")
        if name == "access":
            tint = config.get("access_colors", {}).get(value.strip("[]"), tint)
        if name in ("context", "five_hour", "weekly"):
            percent = float(value)
            tint = config.get("critical_color", "red") if percent > config.get("critical_percent", 95) else (
                config.get("warning_color", "yellow") if percent > config.get("warning_percent", 80)
                else config.get("usage_color", "green"))
            value = f'{config.get(name + "_label", name)} {percent:g}%'
        if name == "tokens":
            value = f'{config.get("tokens_label", "spent")} {value}'
        if name == "credits" and value == "limit":
            tint = config.get("critical_color", "red")
        return [(clean(value), color(tint))]

    def side(items):
        groups = []
        for item in items:
            if isinstance(item, list):
                if not any(field(part) for part in item if part in names):
                    continue
                group = [piece for part in item for piece in (
                    field(part) if part in names else [(clean(part), color("text"))])]
            else:
                group = field(item)
            if group:
                if groups:
                    groups.append((config.get("separator", " · "), color(config.get("separator_color", "text"))))
                groups.extend(group)
        return groups

    left, right = side(config["left"]), side(config["right"])
    def cells(parts):
        return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in ("W", "F") else 1
                   for text, _ in parts for c in text)
    spacing = max(1, width - 2 - cells(left) - cells(right))
    background = color(config.get("background_color", "surface0"))
    return "".join(f"#[fg={tint},bg={background}]{value}" for value, tint in
                   left + [(" " * spacing, color("text"))] + right) + "#[default]"


class Pane:
    def __init__(self):
        self.process = None
        self.process_checked = 0
        self.process_started = 0
        self.log_id = None
        self.log = None
        self.offset = 0
        self.log_generation = None
        self.pending = b""
        self.log_state = {}
        self.sample = {}
        self.transcript = None
        self.transcript_offset = 0
        self.transcript_generation = None
        self.transcript_pending = b""
        self.permission = None
        self.git_key = None
        self.git_checked = 0
        self.git_values = ("", "")
        self.published = None
        self.published_at = 0

    def codex(self, agent, session_id, cwd):
        now = time.monotonic()
        if now - self.process_checked >= 1:
            info = rpc("pane.process_info", {"pane_id": agent["pane_id"]})["process_info"]
            process = next((p for p in info["foreground_processes"]
                            if Path(p["argv"][0]).name in ("codex", ".codex-wrapped")), None)
            if process != self.process:
                started = 0
                if process:
                    stamp = command("env", "LC_ALL=C", "ps", "-p", str(process["pid"]), "-o", "lstart=").strip()
                    started = time.mktime(time.strptime(stamp, "%a %b %d %H:%M:%S %Y"))
                self.process, self.process_started = process, started
            self.process_checked = now
        if self.process:
            native_path = codex_home / "herdr" / f'{self.process["pid"]}.json'
            native = read_json(native_path)
            if (native and native.get("socket") == socket_path
                    and native.get("pid") == self.process["pid"]
                    and native_path.stat().st_mtime >= self.process_started):
                sample = dict(native)
                sample["sandbox"] = (sample.get("sandbox") or {}).get("type")
                return sample
        if session_id:
            if session_id != self.log_id:
                self.log_id, self.log, self.offset = session_id, None, 0
                self.pending, self.log_state, self.sample = b"", {}, {}
            if self.log is None:
                self.log = next((codex_home / "sessions").rglob(f"*-{session_id}.jsonl"), None)
            if self.log is None:
                return {}
            stat = self.log.stat()
            generation = (stat.st_ino, stat.st_birthtime)
            if generation != self.log_generation or stat.st_size < self.offset:
                self.offset, self.pending, self.log_state, self.sample = 0, b"", {}, {}
                self.log_generation = generation
            if stat.st_size != self.offset:
                with self.log.open("rb") as stream:
                    stream.seek(self.offset)
                    data = self.pending + stream.read()
                    self.offset = stream.tell()
                complete, _, self.pending = data.rpartition(b"\n")
                if complete:
                    self.log_state = json.loads(command(
                        "jq", "-Rnc", "--argjson", "previous", json.dumps([self.log_state]),
                        "-f", str(scripts / "collect.jq"), input=complete.decode() + "\n"))
                    self.sample = json.loads(command("jq", "-c", "-f", str(scripts / "codex-metrics.jq"),
                                                     input=json.dumps(self.log_state)))
            return self.sample
        if not self.process:
            return {}
        directory = root / f'start-{agent["terminal_id"]}-{self.process["pid"]}'
        directory.mkdir(exist_ok=True)
        sample = read_json(directory / "start-data.json")
        if sample is None:
            args = self.process["argv"]
            overrides = []
            for i, arg in enumerate(args[:-1]):
                key = {"-m": "model", "--model": "model", "-s": "sandbox_mode", "--sandbox": "sandbox_mode",
                       "-a": "approval_policy", "--ask-for-approval": "approval_policy"}.get(arg)
                if arg in ("-c", "--config"):
                    overrides.extend(("-c", args[i + 1]))
                elif key:
                    overrides.extend(("-c", f"{key}={json.dumps(args[i + 1])}"))
            if any(arg in args for arg in ("--yolo", "--dangerously-bypass-approvals-and-sandbox")):
                overrides.extend(("-c", 'sandbox_mode="danger-full-access"', "-c", 'approval_policy="never"'))
            subprocess.run(["bash", str(scripts / "codex-start-data.sh"), str(directory), *overrides],
                           cwd=cwd, check=True, stdout=subprocess.DEVNULL)
            sample = read_json(directory / "start-data.json")
        return sample

    def claude(self, session_id):
        sample = read_json(root / "claude" / f"{session_id}.json") or {}
        # The status line reports no permission mode, so follow the transcript it names instead.
        named = sample.get("transcript")
        if not named:
            return sample
        path = Path(named)
        if path != self.transcript:
            self.transcript, self.transcript_generation = path, None
        try:
            info = path.stat()
        except OSError:
            return sample
        generation = (info.st_ino, info.st_birthtime)
        if generation != self.transcript_generation or info.st_size < self.transcript_offset:
            # A replaced transcript is read whole, so a mode set before this pane opened is seen.
            self.transcript_offset, self.transcript_pending, self.permission = 0, b"", None
            self.transcript_generation = generation
        if info.st_size != self.transcript_offset:
            with path.open("rb") as stream:
                stream.seek(self.transcript_offset)
                data = self.transcript_pending + stream.read()
                self.transcript_offset = stream.tell()
            complete, _, self.transcript_pending = data.rpartition(b"\n")
            for match in MODE_RECORD.finditer(complete):
                try:
                    record = json.loads(match.group())
                except ValueError:
                    continue
                # Message records carry the mode too, and a switch can be recorded only there.
                # Reading the top level ignores a record that merely mentions the field.
                mode = record.get("permissionMode")
                if isinstance(mode, str) and mode:
                    self.permission = mode
        return dict(sample, permission=self.permission) if self.permission else sample

    def publish(self, agent):
        provider, session_id = identity(agent)
        if session_id and not re.fullmatch(r"[a-zA-Z0-9_-]+", session_id):
            return
        cwd = agent.get("foreground_cwd") or agent["cwd"]
        sample = (self.codex(agent, session_id, cwd) if provider == "codex"
                  else self.claude(session_id)) or {}
        now = time.monotonic()
        if cwd != self.git_key or now - self.git_checked >= 5:
            try:
                worktree = command("git", "-C", cwd, "rev-parse", "--show-toplevel").strip()
                branch = command("git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD").strip()
                if branch == "HEAD":
                    branch = command("git", "-C", cwd, "rev-parse", "--short", "HEAD").strip()
            except subprocess.CalledProcessError:
                worktree, branch = cwd, ""
            self.git_key, self.git_checked, self.git_values = cwd, now, (Path(worktree).name, branch)
        permission, sandbox = sample.get("permission"), sample.get("sandbox")
        if permission == "bypassPermissions" or (sandbox == "danger-full-access" and sample.get("approval") == "never"):
            access = "bypass"
        else:
            access = sample.get("permission_label", "").lower() or {
                "acceptEdits": "auto edits", "auto": "auto", "plan": "plan", "default": "ask",
            }.get(permission) or {
                "danger-full-access": "full access", "workspace-write": "workspace", "read-only": "read only",
            }.get(sandbox, "")
        model, effort = sample.get("model"), sample.get("effort")
        # Codex sets a collaboration mode beside its sandbox; the default one is worth no room.
        mode = sample.get("mode")
        mode = mode.lower() if isinstance(mode, str) and mode.lower() != "default" else None
        tokens = {"footer_session": session_id, "footer_terminal": agent["terminal_id"] if not session_id else None,
                  "footer_left": None, "footer_access": f"[{access}]" if access else None,
                  "footer_mode": f"[{mode}]" if mode else None,
                  "footer_dir": self.git_values[0], "footer_branch": self.git_values[1] or None,
                  "footer_model": " ".join(v for v in (model, effort) if isinstance(v, str)),
                  "footer_model_name": model, "footer_effort": effort}
        spent = sample.get("session_tokens")
        tokens["footer_tokens"] = compact(spent) if isinstance(spent, (int, float)) and spent >= 0 else None
        quota = share_quota(provider, sample)
        # Past the limit the account runs on credits, which is worth saying out loud.
        exhausted = any(isinstance(quota_value(quota, key), (int, float))
                        and quota_value(quota, key) >= 100 for key in ("five_hour", "weekly"))
        tokens["footer_credits"] = None if not exhausted else (
            "credits" if quota.get("has_credits") else "limit")
        for key, token in (("context", "footer_ctx"), ("five_hour", "footer_5h"), ("weekly", "footer_week")):
            value = sample.get(key) if key == "context" else quota_value(quota, key)
            tokens[token] = str(value) if isinstance(value, (int, float)) else None
        tokens = {k: v[:80] if isinstance(v, str) else v for k, v in tokens.items()}
        if tokens == self.published and now - self.published_at < 5:
            return
        # A late sample cannot repaint a replaced session or a moved pane's old occupant.
        current = next((a for a in rpc("agent.list")["agents"]
                        if a["terminal_id"] == agent["terminal_id"] and identity(a) == identity(agent)), None)
        if current is None:
            return
        if provider == "codex" and self.process:
            info = rpc("pane.process_info", {"pane_id": current["pane_id"]})["process_info"]
            if not any(p["pid"] == self.process["pid"] for p in info["foreground_processes"]):
                return
        rpc("pane.report_metadata", {"pane_id": current["pane_id"], "source": "user:pane-footer",
                                      "ttl_ms": 15000, "tokens": tokens})
        self.published, self.published_at = tokens, now


def scan_claude_quota():
    # Every session's last reading is on disk, including sessions with no pane open.
    for path in (root / "claude").glob("*.json"):
        share_quota("claude", read_json(path) or {})


def account_usage():
    """Codex serves account usage read-only, so an idle pane need not wait for a logged turn."""
    directory = root / "codex-quota"
    directory.mkdir(exist_ok=True)
    while not stop.is_set():
        with state_lock:
            present = any(a.get("agent") == "codex" for a in agents.values())
        if not present:
            # Poll at the sampling rate until there is a Codex pane worth keeping current.
            stop.wait(INTERVAL)
            continue
        try:
            subprocess.run(["bash", str(scripts / "codex-start-data.sh"), str(directory)],
                           cwd=str(Path.home()), check=True, stdout=subprocess.DEVNULL)
            share_quota("codex", read_json(directory / "start-data.json") or {})
        except Exception:
            report("footer account usage refresh failed")
        stop.wait(QUOTA_INTERVAL)


def worker(terminal):
    pane, failures = Pane(), 0
    while not stop.is_set():
        with state_lock:
            agent = agents.get(terminal)
        if agent is None:
            return
        try:
            pane.publish(agent)
            failures = 0
        except Exception:
            failures += 1
            report("footer sample failed", terminal=terminal, attempt=failures)
        if once:
            return
        stop.wait(interval(failures))


for number in (signal.SIGINT, signal.SIGTERM):
    signal.signal(number, lambda *_: stop.set())
scan_claude_quota()
if not once:
    threading.Thread(target=account_usage, daemon=True).start()
failures = 0
try:
    while not stop.is_set() and socket_generation() == generation:
        try:
            current = rpc("agent.list")["agents"]
            with state_lock:
                # Restoring terminals appear in the snapshot before their agent is known.
                agents = {a["terminal_id"]: a for a in current if a.get("agent") in ("codex", "claude")}
            for terminal in [t for t in workers if t not in agents and not workers[t].is_alive()]:
                del workers[terminal]
            for terminal in agents:
                if terminal not in workers or not workers[terminal].is_alive():
                    workers[terminal] = threading.Thread(target=worker, args=(terminal,), daemon=True)
                    workers[terminal].start()
            failures = 0
        except Exception:
            # One unusable snapshot must not end footer updates for the whole session.
            if once:
                raise
            failures += 1
            report("footer agent lookup failed", attempt=failures)
        if once:
            for thread in workers.values():
                thread.join()
            break
        stop.wait(interval(failures))
except (FileNotFoundError, ConnectionError):
    pass
finally:
    stop.set()
PY

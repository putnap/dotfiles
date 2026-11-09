// The ports each checkout's servers listen on: TCP listeners whose process works inside it, which
// is where a dev server started in a worktree runs. Apps outside any checkout (at /) never match,
// and agents are left out: every Claude listens on a localhost port of its own for its IDE bridge.
import { exec } from "herdr";

const AGENTS = new Set(["claude", "codex"]);

// { top: [{ port, command }, ...] } for the checkouts on this machine that have any, by port.
export async function askPorts(tops) {
  const listening = await exec("lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]);
  const servers = processes(listening.stdout).filter((p) => !AGENTS.has(p.command) && p.names.length > 0);
  if (servers.length === 0) return {};
  const folders = await exec("lsof", ["-a", "-d", "cwd", "-p", servers.map((p) => p.pid).join(","), "-Fpn"]);
  const folderOf = Object.fromEntries(processes(folders.stdout).map((p) => [p.pid, p.names[0]]));
  const found = {};
  for (const server of servers) {
    const top = checkoutOf(folderOf[server.pid], tops);
    if (!top) continue;
    const ports = server.names.map(portOf).filter(Boolean).map((port) => ({ port, command: server.command }));
    found[top] = uniqueByPort([...(found[top] ?? []), ...ports]);
  }
  return found;
}

// lsof -F prints "p<pid>", then "c<command>" and "n<name>" lines for that process.
function processes(text) {
  const list = [];
  for (const line of text.split("\n")) {
    if (line.startsWith("p")) list.push({ pid: line.slice(1), command: "", names: [] });
    else if (line.startsWith("c") && list.length) list.at(-1).command = line.slice(1);
    else if (line.startsWith("n") && list.length) list.at(-1).names.push(line.slice(1));
  }
  return list;
}

// "*:5173", "127.0.0.1:3000", "[::1]:8080" -> 5173, 3000, 8080
function portOf(name) {
  return Number(name.match(/:(\d+)$/)?.[1]) || null;
}

// A server listening on both IPv4 and IPv6 reports its port twice.
function uniqueByPort(ports) {
  const byPort = new Map(ports.map((p) => [p.port, p]));
  return [...byPort.values()].sort((a, b) => a.port - b.port);
}

// The deepest checkout holding the folder, so a worktree nested in its repo wins over the repo.
function checkoutOf(folder, tops) {
  if (!folder) return null;
  const holding = tops.filter((top) => folder === top || folder.startsWith(top + "/"));
  return holding.sort((a, b) => b.length - a.length)[0] ?? null;
}

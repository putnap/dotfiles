// When each idle Claude agent's prompt cache expires. Claude caches the conversation for an hour
// (its transcripts write only 1h cache) from its last request, which ends its turn; the next
// message after that rewrites the whole context, the costly part of a long session.
import { exec, hc } from "herdr";

const CACHE_MS = 60 * 60 * 1000;

// { address: expiresAt } for every Claude agent that is not mid-turn.
export async function askCacheExpiries(agents) {
  const idle = agents.filter((agent) => agent.app === "claude-code" && agent.status !== "working");
  const entries = await Promise.all(idle.map(async (agent) => [agent.address, await askExpiry(agent.address)]));
  return Object.fromEntries(entries.filter(([, expiresAt]) => expiresAt));
}

// Claude keeps each running process's state in sessions/<pid>.json: statusUpdatedAt is when it
// last went idle (or started waiting on you), the end of its last request.
async function askExpiry(address) {
  const shown = await hc(["get", address, "--json"]);
  const pid = shown.code === 0 ? JSON.parse(shown.stdout).foreground?.pid : null;
  if (!pid) return null;
  const file = await exec("sh", ["-c", 'cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/$1.json"', "sh", String(pid)]);
  const session = file.code === 0 ? parseSession(file.stdout) : null;
  return !session || session.status === "busy" || !session.statusUpdatedAt ? null : session.statusUpdatedAt + CACHE_MS;
}

// Claude rewrites the file while it runs, so a read can land mid-write.
function parseSession(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// herdr's keys (~/.config/herdr/config.toml) where herdr-app has no command for them. The layout
// docks a hidden copy that takes "keys.<command>" from keys.json; "keys.prefix" opens a second copy
// as a popup that takes the key after ctrl+\, as herdr's prefix does, and lists what each one does.
// The popup hands the key back to the docked copy to act on: it closes as the key is pressed, and
// with it anything it had started (a lazygit popup waiting on its terminal) would stop.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, hc, exec, home, appHome, readTextFile, keys, panes, focused, agents, props, openOverlay, closeOverlay, nextCommand, notify, theme, shared, setShared } from "herdr";

const DEFAULT_AGENT = ["claude"];
const NAV_KEYS = { left: "ctrl+h", down: "ctrl+j", up: "ctrl+k", right: "ctrl+l" };
const NVIM_KEYS = { left: "<C-h>", down: "<C-j>", up: "<C-k>", right: "<C-l>" };

// What keys.json sends this mod, by command.
const COMMANDS = {
  prefix: () => openOverlay({ mod: "keys", kind: "dialog", width: 980, height: 440, props: { prefix: true } }),
  "nav-left": () => navigate("left"),
  "nav-down": () => navigate("down"),
  "nav-up": () => navigate("up"),
  "nav-right": () => navigate("right"),
  "break-pane": () => breakPane(),
  "hunk-open": () => openHunk(),
  lazygit: () => popup(["lazygit"]),
  pressed: () => PREFIX[shared("keys.pressed")]?.[1](),
  press: (key) => PREFIX[key]?.[1](),
  help: () => keyHelp(),
};

// The keys after the prefix, in the groups the popup shows: key → [what it does, action]. Chords
// are keystrokes ("ctrl-g"); shifted keys are the character they type ("X", "$"), so they hold
// on any keyboard layout. Keys sharing a label show as one row.
const PREFIX_GROUPS = {
  Tabs: {
    c: ["new", () => run("tab.new")],
    C: ["new with the agent", () => run("tab.new", { argv: DEFAULT_AGENT })],
    n: ["next", () => run("tab.next")],
    p: ["previous", () => run("tab.prev")],
    ",": ["rename", () => run("tab.rename")],
    T: ["rename", () => run("tab.rename")],
    "&": ["close", () => run("tab.close")],
    X: ["close", () => run("tab.close")],
    ...tabNumberKeys(),
  },
  Spaces: {
    s: ["go to…", () => run("mod.open", { name: "picker" })],
    w: ["go to…", () => run("mod.open", { name: "picker" })],
    "ctrl-o": ["go to…", () => run("mod.open", { name: "picker" })],
    N: ["new", () => run("space.new")],
    "$": ["rename", () => run("space.rename")],
    W: ["rename", () => run("space.rename")],
    D: ["close", () => run("space.close")],
    "ctrl-g": ["new or open worktree", () => worktreePicker()],
    "ctrl-x": ["remove worktree", () => worktree("remove", 440, 260)],
  },
  Panes: {
    v: ["split right", () => run("pane.split", { direction: "right" })],
    "|": ["split right", () => run("pane.split", { direction: "right" })],
    "-": ["split down", () => run("pane.split", { direction: "down" })],
    j: ["go down", () => run("pane.go", { direction: "down" })],
    k: ["go up", () => run("pane.go", { direction: "up" })],
    l: ["go right", () => run("pane.go", { direction: "right" })],
    o: ["next", () => cyclePane()],
    tab: ["next", () => cyclePane()],
    ";": ["last", () => lastPane()],
    K: ["swap up", () => run("pane.swap", { direction: "up" })],
    J: ["swap down", () => run("pane.swap", { direction: "down" })],
    "{": ["swap left", () => run("pane.swap", { direction: "left" })],
    "}": ["swap right", () => run("pane.swap", { direction: "right" })],
    z: ["zoom", () => run("pane.zoom")],
    x: ["close", () => run("pane.close")],
  },
  Agent: {
    m: ["pin", () => pinAgent()],
    f: ["fork into a pane", () => forkAgent("right")],
    F: ["fork into a tab", () => forkAgent("tab")],
    "<": ["rename the session", () => renameSession()],
    t: ["past sessions", () => run("mod.open", { name: "atuin-threads" })],
    "alt-m": ["sounds on/off", () => exec("peon", ["toggle"])],
  },
  Review: {
    r: ["hunk on/off", () => toggleHunk()],
    R: ["answer hunk notes", () => askToAnswerNotes()],
    e: ["walkthrough", () => run("mod.open", { name: "walkthrough" })],
    b: ["Blueprint on/off", () => toggleBlueprint()],
  },
  "Git & links": {
    g: ["lazygit", () => popup(["lazygit"])],
    h: ["GitHub dashboard", () => popup(["gh-dash"])],
    i: ["pull request", () => openPullRequest()],
    I: ["Linear issue", () => openIssue()],
  },
  App: {
    "ctrl-s": ["settings", () => run("app.settings")],
    "?": ["all keys", () => keyHelp()],
  },
};
// The popup's columns, top to bottom, by group.
const PREFIX_COLUMNS = [["Tabs", "Spaces"], ["Panes"], ["Agent", "Review"], ["Git & links", "App"]];
const PREFIX = Object.assign({}, ...Object.values(PREFIX_GROUPS));

function tabNumberKeys() {
  const keys = {};
  for (let n = 1; n <= 9; n++) keys[String(n)] = ["go to tab n", () => run("tab.select", { index: n })];
  return keys;
}

export default class Keys extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    if (isPrefixPopup()) cx.timer.after(0, () => this.handle.focus());
    else cx.spawn(async (cx) => receiveCommands(cx));
  }

  render() {
    if (!isPrefixPopup()) {
      rememberFocus();
      return div();
    }
    return prefixPopup(this.handle);
  }
}

async function receiveCommands(cx) {
  for (;;) {
    const command = await nextCommand();
    await runCommand(command);
    cx.notify();
  }
}

// One failing command must not end the loop: every later key would go unanswered.
async function runCommand(command) {
  const { name, value } = commandParts(command);
  try {
    await COMMANDS[name]?.(value);
  } catch (error) {
    notify({ title: `keys: ${command} failed`, body: String(error?.message ?? error), level: "error" });
  }
}

// "press:z" is the command press with the value z, as keys.json's "name:value".
function commandParts(command) {
  const at = command.indexOf(":");
  if (at < 0) return { name: command, value: null };
  return { name: command.slice(0, at), value: command.slice(at + 1) };
}

// which-key's look: every group at once, in columns, the keys in the accent colour.
function prefixPopup(handle) {
  const t = theme();
  const close = () => closeOverlay(props().overlay);
  return v_flex().id("prefix").track_focus(handle).size_full().p(14).gap(10).bg(t.popover).text_size(12)
    .on_key_down((event, cx) => {
      cx.stop_propagation();
      if (isModifierOnly(event.key)) return;
      const key = prefixKey(event);
      close();
      if (key) actOnPrefixKey(key);
    })
    .child(div().text_color(t.foreground).font_semibold().child("ctrl+\\  then…"))
    .child(h_flex().items_start().gap(24).children(PREFIX_COLUMNS.map((groups) => prefixColumn(groups, t))));
}

function prefixColumn(groups, t) {
  return v_flex().flex_1().min_w(0).gap(10).children(groups.map((name) => prefixGroup(name, t)));
}

function prefixGroup(name, t) {
  const rows = prefixRows(PREFIX_GROUPS[name]).map(([label, keys]) =>
    h_flex().h(20).items_center().gap(10)
      .child(div().w(72).flex_none().truncate().text_color(t.accent).font_semibold().child(keys))
      .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(label)));
  return v_flex().gap(2).child(div().h(18).text_size(11).font_medium().text_color(t.dim).child(name)).children(rows);
}

// [label, keys] per row: keys sharing a label join, and a long run shows as its ends ("1…9").
function prefixRows(group) {
  const keysByLabel = new Map();
  for (const [key, [label]] of Object.entries(group)) keysByLabel.set(label, [...(keysByLabel.get(label) ?? []), key]);
  return [...keysByLabel].map(([label, keys]) => [label, keys.length > 3 ? `${keys[0]}…${keys.at(-1)}` : keys.join(" ")]);
}

function prefixKey(event) {
  return [event.keystroke, event.key_char, event.key].find((key) => PREFIX[key]);
}

function actOnPrefixKey(key) {
  setShared("keys.pressed", key);
  run("keys.pressed");
}

function isModifierOnly(key) {
  return ["shift", "control", "alt", "platform", "function", "capslock"].includes(key);
}

// ctrl+hjkl as smart-splits: Neovim gets the key and moves between its own splits, calling back
// at an edge (nvim/lua/plugins/smart-splits.lua); elsewhere the pane moves, and with nowhere to go
// the program gets the key, so ctrl+l still clears and ctrl+h still deletes.
async function navigate(direction) {
  const here = focused();
  if (!here?.terminal) return run("pane.go", { direction });
  if (focusedProgram(here) === "nvim") return pressNvimKey(here.terminal, direction);
  await goPane(direction);
  if (focused()?.pane === here.pane) await pressKey(here.terminal, NAV_KEYS[direction]);
}

// run() only queues the command; focused() shows the move after the app's next turn.
async function goPane(direction) {
  run("pane.go", { direction });
  await exec("true", []);
}

// Neovim listens on a socket named after its terminal (nvim/lua/plugins/smart-splits.lua): hc keys
// waits until you stop typing (herdr-core #52), the socket doesn't. An nvim without one gets hc keys.
async function pressNvimKey(terminal, direction) {
  const socket = `${home()}/.local/state/nvim/hc/${terminal}.sock`;
  const sent = await exec("nvim", ["--server", socket, "--remote-send", NVIM_KEYS[direction]]);
  if (sent.code !== 0) await pressKey(terminal, NAV_KEYS[direction]);
}

function focusedProgram(here) {
  return panes().find((p) => p.pane === here.pane)?.program?.key;
}

function pressKey(terminal, key) {
  return hc(["keys", terminal, key]);
}

// herdr's last_pane. The docked copy re-renders on every focus change and notes the pane left.
const focusTrail = { current: null, previous: null };

function rememberFocus() {
  const pane = focused()?.pane;
  if (pane && pane !== focusTrail.current) {
    focusTrail.previous = focusTrail.current;
    focusTrail.current = pane;
  }
}

function lastPane() {
  if (panes().some((p) => p.pane === focusTrail.previous)) run("pane.focus", { pane: focusTrail.previous });
}

function cyclePane() {
  const here = focused();
  const tabPanes = panes().filter((p) => p.tab === here?.tab);
  const at = tabPanes.findIndex((p) => p.pane === here?.pane);
  if (tabPanes.length > 1) run("pane.focus", { pane: tabPanes[(at + 1) % tabPanes.length].pane });
}

// herdr's break-pane: the terminal leaves its split and comes back as a tab of its own.
function breakPane() {
  const terminal = focused()?.terminal;
  if (!terminal) return;
  run("terminal.park", { terminal });
  run("terminal.keep", { terminal, place: "tab" });
}

// herdr's popup commands: a terminal over the window that closes when its program exits.
async function popup(argv, width = 0.9, height = 0.9) {
  const cwd = focused()?.cwd ?? undefined;
  const started = await hc(["run", "--bg", "--json", ...(cwd ? ["--cwd", cwd] : []), "--", ...argv]);
  if (started.code !== 0) return notify({ title: `${argv[0]} didn't start`, body: started.stderr, level: "error" });
  const { address } = JSON.parse(started.stdout);
  openOverlay({ kind: "dialog", width, height, layout: { type: "block", content: { terminal: address } } });
  run("pane.focus", { terminal: address });
  return address;
}

// The fzf pickers at herdr's 70% × 60% of the window, kept within sizes that read well on a
// laptop and on an ultrawide.
const PICKER = { width: { share: 0.7, min: 1200, max: 1500 }, height: { share: 0.6, min: 700, max: 900 } };

async function worktreePicker() {
  const size = await windowSize();
  popup(["bash", `${appHome()}/mods/git-worktree/pick.sh`], fit(size.width, PICKER.width), fit(size.height, PICKER.height));
}

// A share of the window's side in px, between min and max, and never past the window. Unknown
// side: the plain share.
function fit(side, { share, min, max }) {
  if (!side) return share;
  return Math.min(side * 0.95, Math.max(min, Math.min(max, side * share)));
}

// ctrl+?: every key in one fzf list. The popup's terminal is watched without blocking the command
// loop, so other keys still answer while the list is open.
const KEY_HELP_CHOICE = "/tmp/herdr-app-keys-help.choice";
const PREFIX_SHOWN = "prefix";

async function keyHelp() {
  const size = await windowSize();
  const argv = ["bash", `${appHome()}/mods/keys/help.sh`, keyHelpRows(), KEY_HELP_CHOICE];
  const terminal = await popup(argv, fit(size.width, PICKER.width), fit(size.height, PICKER.height));
  if (terminal) runChosenKeyOnExit(terminal);
}

// The prefix's keys first, by group, then keys.json's, by section: "action<TAB>keys  what  where".
function keyHelpRows() {
  const prefixed = Object.entries(PREFIX_GROUPS).flatMap(([group, entries]) =>
    Object.entries(entries).map(([key, [what]]) => keyHelpRow(`keys.press:${key}`, `${PREFIX_SHOWN} ${readableKeys(key)}`, what, group)));
  const bound = keys().map((k) => keyHelpRow(k.action, readableKeys(k.keys), actionLabel(k.action), k.section));
  return [...prefixed, ...bound].join("\n");
}

function keyHelpRow(action, shownKeys, what, where) {
  return `${action}\t${shownKeys.padEnd(24)} ${what.padEnd(36)} ${where}`;
}

// keys.json's ctrl-shift-j reads as ctrl+shift+j; a last "-" is the minus key itself.
function readableKeys(chord) {
  return chord.replace(/-(?=.)/g, "+");
}

function actionLabel(action) {
  if (action.startsWith("send:")) return `type ${JSON.stringify(action.slice(5))}`;
  const { name, value } = commandParts(action);
  return [name.replace(/[._-]/g, " "), value].filter(Boolean).join(" ");
}

async function runChosenKeyOnExit(terminal) {
  try {
    await waitForExit(terminal);
    const action = (await readTextFile(KEY_HELP_CHOICE))?.trim();
    if (action) await runAction(action);
  } catch (error) {
    notify({ title: "keys: the chosen key failed", body: String(error?.message ?? error), level: "error" });
  }
}

// hc wait checks in every few minutes while the terminal still runs.
async function waitForExit(terminal) {
  for (;;) {
    const waited = await hc(["wait", terminal, "--json"]);
    if (waited.code !== 0 || JSON.parse(waited.stdout).reason !== "timeout") return;
  }
}

// herdr-app do takes keys.json's actions as written: "tab.select:1", "keys.press:z".
async function runAction(action) {
  const done = await exec("herdr-app", ["do", action]);
  if (done.code !== 0) notify({ title: `${action} can't run from here`, body: done.stdout || done.stderr, level: "error" });
}

// herdr-app has no window-size API; it saves the window's bounds [x, y, width, height] in
// window.json as the window moves. 0 × 0 when it can't be read.
async function windowSize() {
  const text = await readTextFile(`${appHome()}/window.json`).catch(() => null);
  const bounds = text ? JSON.parse(text).bounds : null;
  return bounds ? { width: bounds[2], height: bounds[3] } : { width: 0, height: 0 };
}

// git-worktree is Herdr's worktree mod cloned to put checkouts where herdr's own flow does.
function worktree(action, width, height) {
  const here = focused();
  openOverlay({ mod: "git-worktree", kind: "dialog", width, height, props: { space: here?.space, folder: here?.cwd, action } });
}

// herdr's agent fork (agents/.config/agent-setup/control.sh fork): the focused Claude session
// resumed as a copy, in its permission mode, beside it or in a tab.
async function forkAgent(place) {
  const session = await focusedClaudeSession();
  if (!session) return notify({ title: "No Claude session to fork", body: "The focused pane runs no Claude", level: "error" });
  const argv = ["claude", "--resume", session.sessionId, "--fork-session", ...(await permissionMode(session.sessionId))];
  run("terminal.open", { argv, folder: session.cwd, place });
}

async function renameSession() {
  const session = await focusedClaudeSession();
  if (!session) return notify({ title: "No Claude session to rename", body: "The focused pane runs no Claude", level: "error" });
  openOverlay({ mod: "rename-session", kind: "dialog", width: 420, height: 210, props: { terminal: focused().terminal, name: session.name ?? "" } });
}

// Claude keeps each running process's session (id, cwd, name) in sessions/<pid>.json.
async function focusedClaudeSession() {
  const terminal = focused()?.terminal;
  if (!terminal) return null;
  const shown = await hc(["get", terminal, "--json"]);
  const pid = shown.code === 0 ? JSON.parse(shown.stdout).foreground?.pid : null;
  if (!pid) return null;
  const file = await exec("sh", ["-c", 'cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/$1.json"', "sh", String(pid)]);
  return file.code === 0 ? JSON.parse(file.stdout) : null;
}

// The mode the session last ran in, from its transcript, which can be too long to read whole.
async function permissionMode(sessionId) {
  const found = await exec("sh", ["-c", 'grep -ho \'"permissionMode":"[A-Za-z]*"\' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$1".jsonl | tail -n 1', "sh", sessionId]);
  const mode = found.stdout.match(/"permissionMode":"([A-Za-z]+)"/)?.[1];
  return mode ? ["--permission-mode", mode] : [];
}

// Blueprint draws beside the agent in a pane of its own: the key opens it, or closes the tab's.
// hunk (a terminal diff viewer) reviews the focused checkout in a pane beside it: notes you write
// with c, and the agent's replies, show beside the code while its window stays open.
const HUNK_ARGV = ["hunk", "diff", "--watch", "--transparent-bg", "--agent-notes"];

async function toggleHunk() {
  const shown = hunkPane();
  if (shown) run("pane.close", { pane: shown.pane });
  else await openHunk();
}

async function openHunk() {
  const shown = hunkPane();
  if (shown) run("pane.focus", { pane: shown.pane });
  else run("pane.split", { direction: "right", argv: [...HUNK_ARGV, ...(await reviewBase(focused()?.cwd))] });
}

// hunk diffs the working tree against where the branch left origin's main, so committed and
// uncommitted work show together; on a clean main with nothing unpushed, the last commit.
const REVIEW_BASE = [
  'base=$(git merge-base origin/HEAD HEAD) || exit 0',
  'if [ "$base" = "$(git rev-parse HEAD)" ] && [ -z "$(git status --porcelain)" ]; then base=HEAD~1; fi',
  'echo "$base"',
].join("\n");

async function reviewBase(cwd) {
  const found = await exec("sh", ["-c", REVIEW_BASE], { cwd });
  const base = found.stdout.trim();
  return base ? [base] : [];
}

function hunkPane() {
  const tab = focused()?.tab;
  return panes().find((p) => p.tab === tab && p.program?.name === "hunk") ?? null;
}

// The tab's agent gets how to answer, so it needs no hunk skill: list your notes, reply to each.
const ANSWER_NOTES = [
  "Answer my review notes in the live Hunk window for this repository.",
  "Read them with `hunk session comment list --repo . --type user --json`,",
  "then reply in each note's own thread with `hunk session comment apply --repo . --stdin --focus`, one item per note",
  "({\"replyTo\": <its noteId>, \"summary\": <your answer>, \"author\": \"Claude\"}).",
  "Keep each answer to one or two plain sentences: no rationale, no quoting the note;",
  "change code only where a note asks for it.",
].join(" ");

async function askToAnswerNotes() {
  const tab = focused()?.tab;
  const agent = agents().find((a) => a.tab === tab);
  if (!agent) return notify({ title: "No agent in this tab", body: "Start one to answer the hunk notes", level: "info" });
  await hc(["send", agent.address, ANSWER_NOTES]);
}

function toggleBlueprint() {
  const tab = focused()?.tab;
  const shown = panes().find((p) => p.tab === tab && p.mod === "blueprint");
  if (shown) run("pane.close", { pane: shown.pane });
  else run("pane.split", { direction: "right", mod: "blueprint" });
}

function focusedAgent() {
  const here = focused();
  return agents().find((a) => a.pane === here?.pane);
}

function pinAgent() {
  const agent = focusedAgent();
  if (agent) run("terminal.pin", { terminal: agent.address, pinned: !agent.pinned });
}

// Linear's links come from its bot's comment on the pull request (as herdr's sidebar/open.sh).
const LINEAR_ISSUE = /https:\/\/linear\.app\/[\w-]+\/issue\/[A-Za-z]+-\d+/;
const LINEAR_REVIEW = /https:\/\/linear\.app\/[\w-]+\/review\/[\w-]+/;
const LINEAR_WORKSPACE = /https:\/\/linear\.app\/([\w-]+)\//;

// herdr's prefix+i and prefix+shift+i (sidebar/open.sh): the pull request where it's reviewed,
// Linear's review when the repo is wired to Linear, else GitHub; and its Linear issue, which
// before there is a pull request the branch's ticket still names.
async function openPullRequest() {
  const cwd = focused()?.cwd;
  const links = await pullRequestLinks(cwd);
  const url = links?.review ?? links?.github;
  if (url) await exec("open", [url]);
  else notify({ title: "No pull request", body: `for ${cwd}`, level: "info" });
}

async function openIssue() {
  const cwd = focused()?.cwd;
  const url = (await pullRequestLinks(cwd))?.issue ?? (await issueFromTicket(cwd));
  if (url) await exec("open", [url]);
  else notify({ title: "No Linear issue", body: `for ${cwd}`, level: "info" });
}

async function pullRequestLinks(cwd) {
  const pr = await exec("gh", ["pr", "view", "--json", "url,body,comments"], { cwd });
  if (pr.code !== 0) return null;
  const view = JSON.parse(pr.stdout);
  const text = pullRequestText(view);
  return { github: view.url, review: text.match(LINEAR_REVIEW)?.[0] ?? null, issue: text.match(LINEAR_ISSUE)?.[0] ?? null };
}

// The Linear workspace is read off the repo's recent pull requests, which its bot links.
async function issueFromTicket(cwd) {
  const branch = await exec("git", ["rev-parse", "--abbrev-ref", "HEAD"], { cwd });
  const ticket = branch.stdout.match(/([A-Za-z]+-\d+)/)?.[1]?.toUpperCase();
  if (!ticket) return null;
  const recent = await exec("gh", ["pr", "list", "--state", "all", "--limit", "5", "--json", "body,comments"], { cwd });
  const workspace = recent.code === 0 ? JSON.parse(recent.stdout).map(pullRequestText).join(" ").match(LINEAR_WORKSPACE)?.[1] : null;
  return workspace ? `https://linear.app/${workspace}/issue/${ticket}` : null;
}

function pullRequestText(pr) {
  return [pr.body ?? "", ...(pr.comments ?? []).map((c) => c.body ?? "")].join(" ");
}

function isPrefixPopup() {
  return Boolean(props()?.prefix);
}

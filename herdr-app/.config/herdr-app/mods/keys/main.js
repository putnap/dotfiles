// herdr's keys (~/.config/herdr/config.toml) where herdr-app has no command for them. The layout
// docks a hidden copy that takes "keys.<command>" from keys.json; "keys.prefix" opens a second copy
// as a popup that takes the key after ctrl+\, as herdr's prefix does, and lists what each one does.
// The popup hands the key back to the docked copy to act on: it closes as the key is pressed, and
// with it anything it had started (a lazygit popup waiting on its terminal) would stop.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, hc, exec, home, panes, focused, agents, props, openOverlay, closeOverlay, nextCommand, notify, theme, shared, setShared } from "herdr";

const DEFAULT_AGENT = ["claude"];
const NAV_KEYS = { left: "ctrl+h", down: "ctrl+j", up: "ctrl+k", right: "ctrl+l" };
const NVIM_KEYS = { left: "<C-h>", down: "<C-j>", up: "<C-k>", right: "<C-l>" };

// What keys.json sends this mod, by command.
const COMMANDS = {
  prefix: () => openOverlay({ mod: "keys", kind: "dialog", width: 300, height: 560, props: { prefix: true } }),
  "nav-left": () => navigate("left"),
  "nav-down": () => navigate("down"),
  "nav-up": () => navigate("up"),
  "nav-right": () => navigate("right"),
  "break-pane": () => breakPane(),
  "hunk-open": () => openHunk(),
  pressed: () => PREFIX[shared("keys.pressed")]?.[1](),
};

// The key after the prefix: [what it does, action]. Chords are keystrokes ("ctrl-g"); shifted
// keys are the character they type ("X", "$"), so they hold on any keyboard layout.
const PREFIX = {
  c: ["new tab", () => run("tab.new")],
  C: ["new tab with the agent", () => run("tab.new", { argv: DEFAULT_AGENT })],
  n: ["next tab", () => run("tab.next")],
  p: ["previous tab", () => run("tab.prev")],
  ",": ["rename tab", () => run("tab.rename")],
  T: ["rename tab", () => run("tab.rename")],
  "&": ["close tab", () => run("tab.close")],
  X: ["close tab", () => run("tab.close")],
  "$": ["rename space", () => run("space.rename")],
  W: ["rename space", () => run("space.rename")],
  N: ["new space", () => run("space.new")],
  D: ["close space", () => run("space.close")],
  x: ["close pane", () => run("pane.close")],
  z: ["zoom pane", () => run("pane.zoom")],
  v: ["split right", () => run("pane.split", { direction: "right" })],
  "|": ["split right", () => run("pane.split", { direction: "right" })],
  "-": ["split down", () => run("pane.split", { direction: "down" })],
  j:["pane down", () => run("pane.go", { direction: "down" })],
  k: ["pane up", () => run("pane.go", { direction: "up" })],
  l: ["pane right", () => run("pane.go", { direction: "right" })],
  K: ["swap pane up", () => run("pane.swap", { direction: "up" })],
  J: ["swap pane down", () => run("pane.swap", { direction: "down" })],
  "{": ["swap pane left", () => run("pane.swap", { direction: "left" })],
  "}": ["swap pane right", () => run("pane.swap", { direction: "right" })],
  o: ["next pane", () => cyclePane()],
  tab: ["next pane", () => cyclePane()],
  ";": ["last pane", () => lastPane()],
  s: ["go to…", () => run("mod.open", { name: "picker" })],
  w: ["go to…", () => run("mod.open", { name: "picker" })],
  "ctrl-o": ["go to…", () => run("mod.open", { name: "picker" })],
  g: ["lazygit", () => popup(["lazygit"])],
  b: ["Blueprint on/off", () => toggleBlueprint()],
  r: ["review in hunk on/off", () => toggleHunk()],
  R: ["ask the agent to answer the hunk notes", () => askToAnswerNotes()],
  e: ["walk through the changes", () => run("mod.open", { name: "walkthrough" })],
  t: ["past agent sessions", () => run("mod.open", { name: "atuin-threads" })],
  h: ["GitHub dashboard", () => popup(["gh-dash"])],
  "ctrl-g": ["new worktree", () => worktree("new", 460, 280)],
  G: ["open worktree", () => worktree("open", 560, 480)],
  "ctrl-x": ["remove worktree", () => worktree("remove", 440, 260)],
  m: ["pin the agent", () => pinAgent()],
  f: ["fork the agent into a pane", () => forkAgent("right")],
  F: ["fork the agent into a tab", () => forkAgent("tab")],
  "<": ["rename the Claude session", () => renameSession()],
  i: ["open the pull request", () => openPullRequest()],
  I: ["open the Linear issue", () => openIssue()],
  "alt-m": ["toggle agent sounds", () => exec("peon", ["toggle"])],
  "ctrl-s": ["settings", () => run("app.settings")],
  "?": ["keys", () => run("app.help")],
};
for (let n = 1; n <= 9; n++) PREFIX[String(n)] = [`tab ${n}`, () => run("tab.select", { index: n })];

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
    await COMMANDS[command]?.();
    cx.notify();
  }
}

function prefixPopup(handle) {
  const t = theme();
  const close = () => closeOverlay(props().overlay);
  const rows = Object.entries(PREFIX).map(([key, [label]]) =>
    h_flex().gap(10).h(20).items_center()
      .child(div().w(56).text_color(t.accent).font_semibold().child(key))
      .child(div().flex_1().truncate().text_color(t.muted).child(label)));
  return v_flex().id("prefix").track_focus(handle).size_full().p(12).gap(2).bg(t.popover).text_size(12)
    .on_key_down((event, cx) => {
      cx.stop_propagation();
      if (isModifierOnly(event.key)) return;
      const key = prefixKey(event);
      close();
      if (key) actOnPrefixKey(key);
    })
    .child(div().pb(6).text_color(t.foreground).font_semibold().child("ctrl+\\  then…"))
    .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().children(rows));
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
async function popup(argv) {
  const cwd = focused()?.cwd ?? undefined;
  const started = await hc(["run", "--bg", "--json", ...(cwd ? ["--cwd", cwd] : []), "--", ...argv]);
  if (started.code !== 0) return notify({ title: `${argv[0]} didn't start`, body: started.stderr, level: "error" });
  const { address } = JSON.parse(started.stdout);
  openOverlay({ kind: "dialog", width: 0.9, height: 0.9, layout: { type: "block", content: { terminal: address } } });
  run("pane.focus", { terminal: address });
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

function toggleHunk() {
  const shown = hunkPane();
  if (shown) run("pane.close", { pane: shown.pane });
  else openHunk();
}

function openHunk() {
  const shown = hunkPane();
  if (shown) run("pane.focus", { pane: shown.pane });
  else run("pane.split", { direction: "right", argv: HUNK_ARGV });
}

function hunkPane() {
  const tab = focused()?.tab;
  return panes().find((p) => p.tab === tab && p.program?.name === "hunk") ?? null;
}

// The tab's agent gets how to answer, so it needs no hunk skill: list your notes, reply to each.
const ANSWER_NOTES = [
  "Answer my review notes in the live Hunk window for this repository.",
  "Read them with `hunk session comment list --repo . --type user --json`,",
  "then reply to each one in Hunk with `hunk session comment apply --repo . --stdin --focus`, one item per note on its own line",
  "({\"filePath\": <its file>, \"newLine\": <first of its newRange> (or \"oldLine\" for a removed line), \"summary\": <your answer>, \"author\": \"Claude\"};",
  "this hunk has no replyTo). Keep each answer to one or two plain sentences: no rationale, no quoting the note;",
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

// Each folder's git checkout and each checkout's pull request, asked of git and gh in the
// background and kept, so drawing never waits. A checkout's ticket is read off its branch.
import { exec } from "herdr";

const CHECKOUT_SECONDS = 30;
const PULL_REQUEST_SECONDS = 180;

export class Git {
  constructor() {
    this.checkouts = {}; // "machine:folder" -> { top, repo, linked, branch, changes, drift } | null outside git
    this.pullRequests = {}; // "machine:top" -> { number, state, url, issue } | null without one
    this.askedAt = {};
  }

  checkout(machine, folder) {
    return folder ? this.checkouts[place(machine, folder)] ?? null : null;
  }

  pullRequest(machine, top) {
    return this.pullRequests[place(machine, top)] ?? null;
  }

  // Asks about every folder and checkout given whose answer is missing or old.
  async refresh(folders, tops) {
    const checkouts = folders.filter(({ machine, folder }) => this.due(`c:${place(machine, folder)}`, CHECKOUT_SECONDS));
    const pulls = tops.filter(({ machine, top }) => this.due(`p:${place(machine, top)}`, PULL_REQUEST_SECONDS));
    await Promise.all([
      ...checkouts.map(async ({ machine, folder }) => { this.checkouts[place(machine, folder)] = await askCheckout(machine, folder); }),
      ...pulls.map(async ({ machine, top }) => { this.pullRequests[place(machine, top)] = await askPullRequest(machine, top); }),
    ]);
    return checkouts.length + pulls.length > 0;
  }

  due(key, seconds) {
    const now = Date.now();
    if (now - (this.askedAt[key] ?? 0) < seconds * 1000) return false;
    this.askedAt[key] = now;
    return true;
  }
}

// Linear ids in branches (feature/eng-2919-flag-ui) say more in less room; else the last segment.
export function ticketOf(branch) {
  if (!branch) return "";
  const id = branch.match(/([A-Za-z]+-\d+)/);
  return id ? id[1].toUpperCase() : branch.split("/").pop();
}

function place(machine, folder) {
  return `${machine ?? ""}:${folder}`;
}

async function askCheckout(machine, folder) {
  try {
    const r = await exec("git", ["rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir", "--abbrev-ref", "HEAD"], { cwd: folder, on: machine });
    if (r.code !== 0) return null;
    const [top, repo, branch] = r.stdout.trim().split("\n");
    const [changes, drift] = await Promise.all([askChanges(machine, top), askDrift(machine, top)]);
    return { top, repo, linked: repo !== `${top}/.git`, branch: branch === "HEAD" ? null : branch, changes, drift };
  } catch {
    return null;
  }
}

// Uncommitted lines added and removed, as t3code's +12 −3; null when there are none.
async function askChanges(machine, top) {
  const r = await exec("git", ["diff", "HEAD", "--shortstat"], { cwd: top, on: machine });
  const added = Number(r.stdout.match(/(\d+) insertion/)?.[1] ?? 0);
  const removed = Number(r.stdout.match(/(\d+) deletion/)?.[1] ?? 0);
  return added + removed > 0 ? { added, removed } : null;
}

// Commits ahead of and behind origin's main (origin/HEAD), as herdr's git_status, as of the last
// fetch; null when level with it or without one.
async function askDrift(machine, top) {
  const r = await exec("git", ["rev-list", "--left-right", "--count", "origin/HEAD...HEAD"], { cwd: top, on: machine });
  if (r.code !== 0) return null;
  const [behind, ahead] = r.stdout.trim().split(/\s+/).map(Number);
  return ahead + behind > 0 ? { ahead, behind } : null;
}

// Linear's links come from its bot's comment on the pull request (as herdr's sidebar/open.sh):
// the issue, and the review Linear keeps of the pull request when the repo is wired to it.
const LINEAR_ISSUE = /https:\/\/linear\.app\/[\w-]+\/issue\/([A-Za-z]+-\d+)[\w-]*/;
const LINEAR_REVIEW = /https:\/\/linear\.app\/[\w-]+\/review\/[\w-]+/;

async function askPullRequest(machine, top) {
  try {
    const r = await exec("gh", ["pr", "view", "--json", "number,state,isDraft,url,body,comments,statusCheckRollup"], { cwd: top, on: machine });
    if (r.code !== 0) return null;
    const pr = JSON.parse(r.stdout);
    const text = [pr.body ?? "", ...(pr.comments ?? []).map((c) => c.body ?? "")].join(" ");
    const issue = text.match(LINEAR_ISSUE);
    return {
      number: pr.number,
      state: pr.state !== "OPEN" ? pr.state.toLowerCase() : pr.isDraft ? "draft" : "open",
      url: pr.url,
      review: text.match(LINEAR_REVIEW)?.[0] ?? null,
      issue: issue ? { id: issue[1].toUpperCase(), url: issue[0] } : null,
      checks: checksOf(pr.statusCheckRollup ?? []),
    };
  } catch {
    return null;
  }
}

// GitHub's checks as one word: "failing" over "running"; passing ones, or none, say nothing.
// A check run reports its conclusion once completed, else its status; a commit status its state.
const FAILED = new Set(["FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED"]);
const RUNNING = new Set(["PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"]);

function checksOf(rollup) {
  const outcomes = rollup.map((check) => check.conclusion || check.state || check.status);
  if (outcomes.some((o) => FAILED.has(o))) return "failing";
  if (outcomes.some((o) => RUNNING.has(o))) return "running";
  return null;
}

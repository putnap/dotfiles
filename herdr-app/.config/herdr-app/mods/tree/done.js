// The Done shelf: worktrees removed lately, from herdr's done.jsonl (one line per removal, written
// by the git-worktree mod and by the herdr TUI's close-space.sh), newest first. Folded by default;
// a row opens its pull request.
import { div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec } from "herdr";
import { ticketOf } from "./git.js";

const SHOWN = 30;
const CARD_HEIGHT = 44;

export async function askDone() {
  const r = await exec("sh", ["-c", `tail -n ${SHOWN} "\${XDG_STATE_HOME:-$HOME/.local/state}/herdr/done.jsonl"`]);
  if (r.code !== 0) return [];
  return r.stdout.split("\n").filter(Boolean).map(parseLine).filter(Boolean).reverse();
}

export function doneShelf(t, done, open, toggle, icons) {
  const head = h_flex().id("tree-done-head").h(32).flex_none().px(16).gap(8).items_center().cursor_pointer().hover((s) => s.bg(t.hover))
    .on_click(toggle)
    .child(div().flex_1().text_size(12).font_medium().text_color(t.dim).child("Done"))
    .child(div().text_size(11.5).text_color(t.dim).child(String(done.length)))
    .child(svg(`${icons}/${open ? "chevron-down" : "chevron-right"}.svg`).size(12).text_color(t.dim));
  return v_flex().flex_none().border_t(1).border_color(t.border)
    .child(head)
    .when(open, (el) => el.child(v_flex().id("tree-done").flex_none().h(Math.min(5, done.length) * CARD_HEIGHT).overflow_y_scrollbar()
      .children(done.map((entry, i) => doneCard(t, entry, i)))));
}

function doneCard(t, entry, i) {
  const pr = entry.pull_request;
  return v_flex().id(`tree-done-${i}`).h(CARD_HEIGHT).flex_none().px(16).justify_center()
    .when(Boolean(pr), (el) => el.cursor_pointer().hover((s) => s.bg(t.hover)).on_click((_e, cx) => cx.open_url(pr.url)))
    .child(div().truncate().text_size(12.5).text_color(t.muted).child(entry.titles?.[0] || entry.branch || "worktree"))
    .child(div().truncate().text_size(11).text_color(t.dim).child(detail(entry)));
}

// js · ENG-2919 · #9919 · 3d
function detail(entry) {
  const repo = entry.repo?.split("/").pop();
  const ticket = entry.branch ? ticketOf(entry.branch) : null;
  const pr = entry.pull_request ? `#${entry.pull_request.number}` : null;
  return [repo, ticket, pr, age(entry.at)].filter(Boolean).join(" · ");
}

function age(at) {
  const days = Math.floor((Date.now() - at) / 86400000);
  if (days >= 1) return `${days}d`;
  const hours = Math.floor((Date.now() - at) / 3600000);
  return hours >= 1 ? `${hours}h` : "now";
}

// A line cut mid-write by a crash would break the whole shelf, so it is skipped instead.
function parseLine(line) {
  try {
    return JSON.parse(line);
  } catch {
    return null;
  }
}

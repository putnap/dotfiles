// clauth's Claude accounts at the foot of the sidebar: which one the global `claude` burns, and
// how much of its 5h and week windows every account has spent, as the sketchybar clauth item shows.
import { div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, hc, run, openOverlay, notify } from "herdr";

// Red from here, as sketchybar's item; yellow on the way there.
const WARN_PCT = 70;
const FULL_PCT = 85;
const ICONS = "mods/workspace-chrome";

// What clauth's daemon last wrote (~/.clauth/status.json); [] when clauth can't be asked.
export async function askAccounts() {
  try {
    const r = await exec("clauth", ["status", "--json"]);
    return r.code === 0 ? JSON.parse(r.stdout).profiles.map(account) : [];
  } catch {
    return [];
  }
}

// Folded, the account in use alone, on clauth's button's line; a click on it shows them all
// under their column heads, and a click on those folds it again.
export function accountsShelf(t, accounts, open, toggle) {
  const inUse = accounts.find((a) => a.active) ?? accounts[0];
  return v_flex().flex_none().border_t(1).border_color(t.border)
    .when(!open, (el) => el.child(foldedRow(t, inUse, toggle)))
    .when(open, (el) => el.child(tableView(t, accounts, toggle)));
}

// The button and name to the left, the numbers and the week's reset to the right, each as wide
// as its text; the sidebar's 16px inset on both sides, less the button's own padding at the left.
function foldedRow(t, a, toggle) {
  return h_flex().id("tree-accounts-folded").h(28).pl(16 - 4.5).pr(16).gap(6).items_center().text_size(12).text_color(t.dim)
    .cursor_pointer().hover((s) => s.bg(t.hover)).on_click(toggle)
    .child(clauthButton(t).ml(0))
    .child(accountName(t, a).flex_1().min_w(0))
    .child(h_flex().flex_none().gap(10)
      .child(percent(t, a, a.fiveHours))
      .child(percent(t, a, a.week))
      .child(div().whitespace_nowrap().child(a.week.resetsAt ? resetLabel(a.week.resetsAt) : "")));
}

// A Fable week fuller than the whole week is the one that stops the account, so it takes the
// week's place.
function account(profile) {
  const windows = profile.windows.map((w) => ({ label: windowLabel(w.label), pct: Math.round(w.utilization_pct ?? 0), resetsAt: w.resets_at }));
  const find = (label) => windows.find((w) => w.label === label) ?? null;
  const weeks = [find("7d"), find("fable")].filter(Boolean);
  return {
    name: profile.name,
    active: profile.active,
    trouble: profile.auth_status !== "ok" ? `auth ${profile.auth_status}` : profile.stale ? "stale" : "",
    fiveHours: find("5h"),
    week: weeks.reduce((most, w) => (w.pct > most.pct ? w : most), weeks[0] ?? { label: "7d", pct: 0, resetsAt: null }),
  };
}

// "7d fable" is the week's Fable allowance: "fable" says it in less room.
function windowLabel(label) {
  return label.toLowerCase().replace(/^7d /, "");
}

// Its icon in line with the account names; a click on it doesn't also fold the shelf.
function clauthButton(t) {
  return h_flex().id("tree-clauth").size(22).ml(-5).flex_none().rounded(4).items_center().justify_center().cursor_pointer()
    .hover((s) => s.bg(t.input)).tooltip("Open clauth")
    .on_click((_e, cx) => { cx.stop_propagation(); openClauth(); })
    .child(svg(`${ICONS}/terminal.svg`).size(13).text_color(t.dim));
}

// Columns of numbers, the week's reset beside them; a window's own reset on hovering its number.
function tableView(t, accounts, toggle) {
  return v_flex()
    .child(tableColumns(t.dim, h_flex().child(clauthButton(t)), "5h", "7d", "").id("tree-accounts-heads").h(24).text_size(11).cursor_pointer().hover((s) => s.bg(t.hover)).on_click(toggle))
    .children(accounts.map((a) => accountRow(t, a, accountName(t, a))));
}

function accountRow(t, a, name) {
  return tableColumns(t.dim, name, percent(t, a, a.fiveHours), percent(t, a, a.week), a.week.resetsAt ? resetLabel(a.week.resetsAt) : "")
    .h(24).text_size(12).when(a.active, (el) => el.bg(t.selected));
}

function tableColumns(color, name, fiveHours, week, resets) {
  return h_flex().px(16).gap(6).items_center().text_color(color)
    .child(name.flex_1().min_w(0))
    .child(div().w(36).flex_none().flex().justify_end().child(fiveHours))
    .child(div().w(36).flex_none().flex().justify_end().child(week))
    .child(div().w(68).flex_none().flex().justify_end().whitespace_nowrap().child(resets));
}

function percent(t, a, w) {
  if (!w) return div().child("–");
  const named = w.label === "fable" ? "f " : "";
  return div().id(`tree-pct-${a.name}-${w.label}`).font_medium().text_color(usageColor(t, w.pct))
    .tooltip(w.resetsAt ? `${w.label} resets ${resetLabel(w.resetsAt)}` : `${w.label}: nothing spent`)
    .child(`${named}${w.pct}%`);
}

function accountName(t, a) {
  return div().truncate().text_color(a.active ? t.accent : t.muted).when(a.active, (d) => d.font_medium())
    .child(a.trouble === "" ? a.name : `${a.name} · ${a.trouble}`);
}

function usageColor(t, pct) {
  return pct >= FULL_PCT ? t.ansi1 : pct >= WARN_PCT ? t.ansi3 : t.ansi2;
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// Within a day, how long; else the weekday and hour it resets, in local time. clauth's times sit
// a moment off the hour (05:59:59.9), so it's the nearest hour.
function resetLabel(resetsAt) {
  const at = new Date(Date.parse(resetsAt) + 30 * 60000);
  const hours = (at.getTime() - Date.now()) / 3600000;
  if (hours < 24) return `in ${Math.max(1, Math.ceil(hours))}h`;
  return `${WEEKDAYS[at.getDay()]} ${String(at.getHours()).padStart(2, "0")}:00`;
}

// clauth's dashboard in a terminal over the window, as the keys mod's lazygit popup.
async function openClauth() {
  const started = await hc(["run", "--bg", "--json", "--", "clauth"]);
  if (started.code !== 0) return notify({ title: "clauth didn't start", body: started.stderr, level: "error" });
  const { address } = JSON.parse(started.stdout);
  openOverlay({ kind: "dialog", width: 0.9, height: 0.9, layout: { type: "block", content: { terminal: address } } });
  run("pane.focus", { terminal: address });
}

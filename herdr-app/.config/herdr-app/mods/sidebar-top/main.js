// The sidebar's one top row, past macOS's window buttons: Herdr's search and sidebar toggle with
// its footer's Add machine and Settings, the command palette (the status bar's hint) and a new
// space, drawn as Herdr's own top row draws its buttons. Its block in the layout drags the window,
// so the buttons keep their presses to themselves.
import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { run, theme, window, layout, keys } from "herdr";

const ICONS = "mods/workspace-chrome";
// Below this the sidebar is the tree's strip of tiles: only the toggle that widens it fits.
const NARROW_WIDTH = 120;
// macOS's three window buttons, from the layout's traffic_lights x to past the last one.
const TRAFFIC_LIGHTS_WIDTH = 64;
const INSET = 16;

const SIDEBAR_TOGGLE = { id: "sidebar-toggle", icon: `${ICONS}/sidebar.svg`, label: "Narrow or widen the sidebar", command: "tree.toggle", action: () => run("tree.toggle") };

const BUTTONS = [
  // Search's lens and the ⌘ draw narrower than the rest at one size, so they're drawn larger to
  // look as wide, and the gaps between them even.
  { id: "search", icon: `${ICONS}/search.svg`, size: 17, label: "Go to…", command: "mod.open:picker", action: () => run("mod.open", { name: "picker" }) },
  // herdr-app draws only icon files that aren't symlinks, as this mod's are once stowed; ⌘ is text.
  { id: "palette", glyph: "⌘", size: 20, label: "Commands", command: "app.palette", action: () => run("app.palette") },
  { id: "add-machine", icon: `${ICONS}/server.svg`, label: "Add machine", command: "mod.open:machine-add", action: () => run("mod.open", { name: "machine-add" }) },
  { id: "settings", icon: `${ICONS}/settings.svg`, label: "Settings", command: "app.settings", action: () => run("app.settings") },
  { id: "new-space", icon: `${ICONS}/square-pen.svg`, label: "New space", command: "space.new", action: () => run("space.new") },
  SIDEBAR_TOGGLE,
];

export default class SidebarTop extends View {
  render() {
    const t = theme();
    if (sidebarWidth() < NARROW_WIDTH) return h_flex().size_full().justify_center().items_center().child(iconButton(t, SIDEBAR_TOGGLE));
    return h_flex().size_full().pl(trafficLightsGap()).pr(10).gap(4).items_center().justify_end()
      .children(BUTTONS.map((b) => iconButton(t, b)));
  }
}

const ICON_SIZE = 15;

function iconButton(t, { id, icon, glyph, size = ICON_SIZE, label, command, action }) {
  return h_flex().id(`sidebar-top-${id}`).size(26).flex_none().items_center().justify_center().cursor_pointer()
    .text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground)).tooltip(withKey(label, command))
    .on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_click(action)
    .child(icon ? svg(icon).size(size) : div().text_size(size).child(glyph));
}

// Room for the window buttons where the layout puts them in the window; none when it puts them
// off its edge (tree.json, as Ghostty's hidden title bar).
function trafficLightsGap() {
  const x = layout()?.traffic_lights?.[0] ?? -1;
  const shown = window()?.platform === "macos" && !window()?.fullscreen && x >= 0;
  return shown ? x + TRAFFIC_LIGHTS_WIDTH : INSET;
}

function sidebarWidth() {
  return find(layout(), "sidebar")?.size?.px ?? Infinity;
}

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// A label with its shortcut as bound now (keys.json), e.g. "Settings  ⌘,"; herdr's old status bar
// read the palette key the same way. Mods can't share files, so the tree, tab bar and top row each
// keep a copy.
const KEY_GLYPHS = { cmd: "⌘", ctrl: "⌃", shift: "⇧", alt: "⌥", option: "⌥" };

function withKey(label, action) {
  const bound = keys().find((k) => k.action === action);
  if (!bound) return label;
  const parts = bound.keys.endsWith("--") ? [...bound.keys.slice(0, -2).split("-"), "-"] : bound.keys.split("-");
  return `${label}  ${parts.map((p) => KEY_GLYPHS[p] ?? p.toUpperCase()).join("")}`;
}

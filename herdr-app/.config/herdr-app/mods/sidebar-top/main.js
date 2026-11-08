// The sidebar's one top row, past macOS's window buttons: Herdr's search and sidebar toggle with
// its footer's Add machine and Settings, the command palette (the status bar's hint) and a new
// space, drawn as Herdr's own top row draws its buttons. Its block in the layout drags the window,
// so the buttons keep their presses to themselves.
import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { run, theme, window, layout } from "herdr";

const ICONS = "mods/workspace-chrome";
// Below this the sidebar is the tree's strip of tiles, too narrow for the row.
const NARROW_WIDTH = 120;
const TRAFFIC_LIGHTS_WIDTH = 76;

const BUTTONS = [
  // Search's lens and the ⌘ draw narrower than the rest at one size, so they're drawn larger to
  // look as wide, and the gaps between them even.
  { id: "search", icon: `${ICONS}/search.svg`, size: 17, label: "Go to…", action: () => run("mod.open", { name: "picker" }) },
  // herdr-app draws only icon files that aren't symlinks, as this mod's are once stowed; ⌘ is text.
  { id: "palette", glyph: "⌘", size: 20, label: "Commands", action: () => run("app.palette") },
  { id: "add-machine", icon: `${ICONS}/server.svg`, label: "Add machine", action: () => run("mod.open", { name: "machine-add" }) },
  { id: "settings", icon: `${ICONS}/settings.svg`, label: "Settings", action: () => run("app.settings") },
  { id: "new-space", icon: `${ICONS}/square-pen.svg`, label: "New space", action: () => run("space.new") },
  { id: "sidebar-toggle", icon: `${ICONS}/sidebar.svg`, label: "Narrow the sidebar", action: () => run("tree.toggle") },
];

export default class SidebarTop extends View {
  render() {
    const t = theme();
    if (sidebarWidth() < NARROW_WIDTH) return div();
    return h_flex().size_full().pl(trafficLightsGap()).pr(10).gap(4).items_center().justify_end()
      .children(BUTTONS.map((b) => iconButton(t, b)));
  }
}

const ICON_SIZE = 15;

function iconButton(t, { id, icon, glyph, size = ICON_SIZE, label, action }) {
  return h_flex().id(`sidebar-top-${id}`).size(26).flex_none().items_center().justify_center().cursor_pointer()
    .text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground)).tooltip(label)
    .on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_click(action)
    .child(icon ? svg(icon).size(size) : div().text_size(size).child(glyph));
}

function trafficLightsGap() {
  return window()?.platform === "macos" && !window()?.fullscreen ? TRAFFIC_LIGHTS_WIDTH : 16;
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

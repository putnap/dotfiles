// Space colours as every shipped mod keeps them (shared "space.colors"), so the sidebar's tiles,
// the tab bar's tint and the picker agree.
import { spaces, shared, setShared } from "herdr";

const MARK = { ansi6: "#22a99a", ansi3: "#e3814f", ansi4: "#5b8def", ansi5: "#8b7cf6", ansi2: "#3fae6a", ansi1: "#d9649a" };
const PROJECT_COLORS = ["ansi6", "ansi3", "ansi4", "ansi5", "ansi2", "ansi1"];

// Each space's colour as the tab bar's tint draws it (mods/tab-bar): its folder's, the tile the
// sidebar shows. A mod can't import another's files, so it reads it from shared state, set only
// when a colour changes.
export function publishSpaceColors(t, folderOf) {
  const colors = Object.fromEntries(spaces().map((space) => [space.id, spaceColor(t, folderOf[space.id] ?? space)]));
  if (JSON.stringify(colors) !== JSON.stringify(shared("tree.space-colors"))) setShared("tree.space-colors", colors);
}

export function spaceColor(t, space) {
  if (space.name === "~") return t.dim;
  const color = spaceColors()[space.id] ?? PROJECT_COLORS[0];
  return color.startsWith("#") ? color : (MARK[color] ?? t[color]);
}

// A space seen without a colour gets the one fewest spaces use, once, as the shipped mods do.
function spaceColors() {
  const ids = new Set(spaces().map((s) => s.id));
  const kept = Object.fromEntries(Object.entries(shared("space.colors") ?? {}).filter(([id]) => ids.has(id)));
  let changed = Object.keys(kept).length !== Object.keys(shared("space.colors") ?? {}).length;
  for (const space of spaces()) {
    if (kept[space.id] || space.name === "~") continue;
    const uses = (c) => Object.values(kept).filter((v) => v === c).length;
    kept[space.id] = PROJECT_COLORS.reduce((best, c) => (uses(c) < uses(best) ? c : best));
    changed = true;
  }
  if (changed) setShared("space.colors", kept);
  return kept;
}

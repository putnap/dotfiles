// The tree's globe: a checkout's listening ports as a popup at the pointer, each opening on
// localhost, drawn as Herdr's context menu. props { ports: [{ port, command }], overlay }.
// ↑/↓ or j/k move, Enter opens, Esc closes.
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, closeOverlay, theme } from "herdr";

// The shipped menu's measures: 31px rows inside 5px of padding. The tree sizes the popup from
// them (mods can't share files, so it keeps the same numbers).
const ROW_HEIGHT = 31;
const PADDING = 5;

export default class Ports extends View {
  init(_props, cx) {
    this.at = 0;
    this.handle = cx.focus_handle();
    cx.timer.after(0, () => this.handle.focus());
  }

  render() {
    const t = theme();
    const ports = props()?.ports ?? [];
    return v_flex().id("ports").track_focus(this.handle).w_full().min_h(0).p(PADDING).bg(t.popover).text_size(12.8)
      .on_key_down((event, cx) => { cx.stop_propagation(); this.key(event.key, ports, cx); })
      .children(ports.map((entry, i) => portRow(t, entry, i === this.at, (cx) => this.open(entry, cx))));
  }

  key(key, ports, cx) {
    const step = MOVES[key];
    if (step) this.at = (this.at + step + ports.length) % ports.length;
    else if (key === "enter") this.open(ports[this.at], cx);
    else if (key === "escape") closeOverlay(props().overlay);
    cx.notify();
  }

  open(entry, cx) {
    cx.open_url(`http://localhost:${entry.port}`);
    closeOverlay(props().overlay);
  }
}

const MOVES = { down: 1, j: 1, up: -1, k: -1 };

function portRow(t, entry, selected, open) {
  return h_flex().id(`ports-${entry.port}`).h(ROW_HEIGHT).px(8).gap(9).rounded(7).items_center().cursor_pointer()
    .text_color(t.foreground)
    .when(selected, (el) => el.bg(t.selected))
    .hover((s) => s.bg(t.hover))
    .on_click((_e, cx) => open(cx))
    .child(svg("mods/tree/globe.svg").size(14).flex_none().text_color(t.muted))
    .child(div().flex_1().child(`localhost:${entry.port}`))
    .child(div().max_w(80).truncate().text_size(11).text_color(t.dim).child(entry.command));
}

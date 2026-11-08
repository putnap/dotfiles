// herdr's prefix+< (herdr/local-plugins/agents/scripts/rename-session.sh): a Claude session's name
// to edit, typed into it as /rename once it waits at its prompt. Saved empty, Claude names it.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { hc, agents, props, closeOverlay, notify, theme } from "herdr";

export default class RenameSession extends View {
  init(_props, cx) {
    const name = props()?.name ?? "";
    this.input = InputState.new({ value: name });
    this.input.set_selected_range({ start: 0, end: name.length });
    this.input.on("submit", () => this.save());
    this.input.focus();
    // As the shipped prompt mod: the dialog can take focus back while it opens.
    cx.timer.after(600, () => this.input.focus());
    this.handle = cx.focus_handle();
  }

  async save() {
    const { terminal, name, overlay } = props();
    const typed = this.input.value();
    closeOverlay(overlay);
    if (typed && typed === name) return;
    if (!waitsAtPrompt(terminal)) return notify({ title: "Claude is busy", body: "Rename it once it waits for you", level: "info" });
    await hc(["send", terminal, renameCommand(typed)]);
  }

  render() {
    const t = theme();
    const close = () => closeOverlay(props().overlay);
    const button = (id, text, primary, action) => h_flex().id(id).h(32).px(14).items_center()
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium().cursor_pointer()
      .hover((s) => s.opacity(0.88)).on_click(action).child(text);
    return v_flex().id("rename-session").track_focus(this.handle)
      .on_key_down((e, cx) => { if (e.key === "escape") { close(); cx.stop_propagation(); } })
      .w_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground)
      .child(div().text_size(15).font_semibold().child("Rename the Claude session"))
      .child(div().pt(6).pb(10).text_size(11.5).text_color(t.dim).child("Empty: Claude names it from the conversation"))
      .child(Input.new(this.input).h(36).px(10).border_1().border_color(t.accent).bg(t.background).text_size(12.8).text_color(t.foreground))
      .child(h_flex().pt(20).gap(8).justify_end()
        .child(button("rename-cancel", "Cancel", false, close))
        .child(button("rename-save", "Save", true, () => this.save())));
  }
}

// Typed while Claude works or asks, the text would queue as a message or answer the question.
function waitsAtPrompt(terminal) {
  const status = agents().find((a) => a.address === terminal)?.status;
  return status === "idle" || status === "done";
}

function renameCommand(name) {
  return name ? `/rename ${name}` : "/rename";
}

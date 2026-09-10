# peon-ping tmux integration

Layers two tmux-aware behaviors onto [peon-ping](https://peonping.com) for
Claude Code:

1. **Click-to-jump** — clicking a notification activates Ghostty and switches
   tmux to the exact session + window that triggered it (window-id based, so it
   survives reindexing).
2. **Always-show banners** — peon's Ghostty focus check can't see inside tmux;
   it falls back to comparing `cwd`, which suppresses the banner whenever the
   focused Ghostty window shares a cwd with (or is simply in front of) the
   pinging one. The wrapper blanks the event `cwd` so peon never suppresses on
   that basis — banners always show while in tmux. (Title still comes from
   `notification_title_script`.)

   Trade-off: you also get a banner for the pane you're already looking at.
   Reliable "am I viewing this exact pane?" detection isn't possible from a tmux
   hook — a Claude window reads as active-in-its-session even when you're
   elsewhere in Ghostty — so we err toward never dropping a notification.

## Files
- `wrapper.sh` — installed as `~/.claude/hooks/peon-ping/peon.sh`; delegates to
  the real engine at `/opt/homebrew/opt/peon-ping/libexec/peon.sh` (so brew
  upgrades still apply).
- `apply.sh` — idempotently links the wrapper and sets the
  `<session> - <window>` notification title in peon's `config.json`.

## Install (fresh machine)
1. `darwin-rebuild switch …` — installs `peon-ping` via brew (in `flake.nix`).
2. `peon-ping-setup` — registers Claude hooks + downloads sound packs.
3. `stow claude` — symlinks this package to `~/.claude/hooks/peon-tmux/`.
4. `~/.claude/hooks/peon-tmux/apply.sh` — wires the wrapper + title.

## Maintenance
`peon-ping-setup` and `peon update` re-link `peon.sh` back to the stock engine,
so **re-run `apply.sh`** after either.

Revert to stock peon-ping:
```sh
ln -sf /opt/homebrew/opt/peon-ping/libexec/peon.sh ~/.claude/hooks/peon-ping/peon.sh
```

## Why a wrapper and not a config option
peon-ping exposes no setting to disable the terminal-frontmost notification
suppression, and its Ghostty focus heuristic (`_ghostty_terminal_is_current`)
compares the focused terminal's title against the bare event title — but peon
writes the tab title as `●…: done`, so that never matches and the decision
collapses onto the `cwd` fallback. The wrapper works around both without
forking the engine.

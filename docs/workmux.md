# Workmux trial

Run tmux directly in a terminal. Herdr and tmux are separate alternatives; neither
runs inside the other. Herdr remains installed during the trial.

The Nix flake pins workmux, supplies tmux to its upstream test environment, and
wraps it with a short temporary path to fit macOS's Unix-socket length limit.
The existing agent installer installs the Claude/Codex hooks with backups and
preserves other integrations. `install.sh` also links the tmux configuration.
For this trial the tested build is also installed in the user Nix profile as
`workmux-eb2867f`; a system rebuild was not needed. Once a later Darwin rebuild
installs workmux system-wide, `nix profile remove workmux-eb2867f` removes that
trial override so it cannot shadow future system updates.

After the package and settings are installed, start a fresh tmux session and fresh
agent processes so they load the hooks:

```sh
tmux new-session -s work
```

If a tmux server was already running, press prefix r to load the updated config.

The first agent opens the sidebar in its session. `Ctrl+Shift+H` toggles it manually.
You can also run `workmux sidebar --session on` from a shell inside tmux.

## Bindings

Prefix is `Ctrl+\`, as in herdr.

| Keys | Action |
| --- | --- |
| Shift+Left/Right | Previous/next window |
| Shift+Up/Down | Previous/next session |
| Ctrl+h/j/k/l | Shared Neovim/tmux navigation through smart-splits |
| Ctrl+Shift+arrows | Shared resize |
| Ctrl+Shift+\ / Ctrl+Shift+- | Split right/below |
| Ctrl+Shift+= | Move pane into its own window |
| Ctrl+Shift+W | Close pane with confirmation |
| Ctrl+Shift+C / prefix C | Default agent in a pane/window |
| Ctrl+Shift+H | Toggle session sidebar |
| Ctrl+Shift+I | Jump to the most recently done/waiting agent |
| prefix a | Agent dashboard and diff review |
| prefix j/k / prefix Alt+1..9 | Sidebar next/previous/direct agent |
| prefix f/F | Fork exact Claude/Codex session into pane/window |
| prefix Alt+c | Choose Claude or Codex for a new window |
| prefix Alt+m | Toggle Peon sound |
| prefix g/h | Lazygit/GitHub dashboard |
| prefix G | Create worktree; ask branch, base and directory name |
| prefix Ctrl+g | Open an existing Git worktree, including agent-created ones |
| prefix s / prefix Ctrl+o | Sessionizer |
| prefix w | Window picker |
| prefix S/R | Save/restore tmux layout and processes |
| prefix Ctrl+r | Workmux's repository-scoped worktree recovery |
| prefix r | Reload tmux and refresh workmux colors |

The worktree creation popup uses workmux's configured worktree root and accepts a
directory name, rather than an arbitrary absolute checkout path. The default
layout is Neovim left, Codex right. `workmux add task -l shell` opens Neovim and a
shell; `-l solo` opens only the agent. `-a claude` uses the same bypass launch mode
as the herdr agent launcher. Codex retains its configured approval/sandbox policy.
Use `workmux close`, `open`, `rebase`, `sync-files`, and `merge` for the native
worktree lifecycle; merge/removal remain explicit commands.

## Theme and footer

Edit tmux's theme. There is no separate workmux palette in the repository.
`~/.config/workmux/defaults.yaml` owns the layout/sidebar settings. Startup combines
it with the active tmux `@thm_*` colors and writes a generated
`~/.config/workmux/config.yaml`; do not edit that generated file. Catppuccin's
flavors follow `@catppuccin_flavor`. Reload tmux after changing theme; other plugins
that expose `@thm_*` work too. Other plugins use the resolved tmux status/current-window
styles where available; unset colors retain workmux's terminal defaults.

The shared collector under `~/.config/herdr/footer` also has a tmux backend. It
uses tmux's socket and pane options, never starts or connects to herdr, and shares
the existing metrics parsers and `pane-footer.toml` field layout. The footer uses
the current tmux palette. Account limits, model/effort, context, session token
spend, permissions and collaboration mode render when the agent provides them.
`spent` is uncached session tokens, not a dollar estimate.

Claude supplies status-line snapshots. Codex uses session logs and read-only
account usage queries. Unlike the native herdr integration, Codex changes made
while idle may not appear until Codex writes them to its log; nothing guesses an
unreported permission mode. Hooks are required for pane identity and sidebar
status, including when starting agents manually.

## Restoration

Tmux resurrect/continuum restores the layout and relaunches Neovim. Neovim owns
its sessions; this change does not modify its saving or loading behavior.
The save hook records exact agent session IDs, retains common model/config,
profile, sandbox/approval and launch-mode overrides, and marks sidebar panes for
reuse during restoration. Original prompts are not replayed. Unsupported custom
CLI flags are not guaranteed to survive; use agent configuration for those.

Workmux's separate `resurrect` command is useful when its worktree windows are
missing, but skips the main checkout and windows already open. Normal full tmux
recovery uses prefix R (or continuum); the save hook covers agent panes in the
main checkout too. Existing tmux saves made before this setup do not have exact
agent IDs. Save once with prefix S after launching fresh agents.

Notifications use the installed Peon hooks and its native tmux click-to-focus
handling. Herdr events continue to use their existing notification route.

## Verification

```sh
bash tests/agent-setup.sh
bash tests/workmux.sh
bash tests/herdr-footer-metrics.sh
bash tests/herdr-footer-startup.sh
bash tests/integration-herdr.sh
HERDR_CONFIG_PATH="$PWD/herdr/.config/herdr/config.toml" herdr config check
nix build "path:$PWD/nix/.config/nix#workmux" --no-link
```

The tests create disposable homes/sockets. They do not send model prompts or
restore the production tmux server. Native terminal key delivery and audible
notifications still deserve an interactive trial.

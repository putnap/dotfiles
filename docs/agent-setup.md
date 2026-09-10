# Shared Claude and Codex setup

The `agents` Stow package owns the shared working agreement, portable skills and native preference fragments. Claude-specific UI files and the council skill remain in the `claude` package. Herdr owns launch/navigation and all Peon notification events. Codex's unattended-run policy is managed separately from Claude's permissions.

## Apply

Refresh everything with one command, from any directory:

```sh
nixr
```

Nix post-activation runs the agent setup as your user, with the newly installed
tools on PATH. It resolves the checkout through `~/.config/nix`, merges settings,
Stows files, installs integrations, registers plugins, and reloads compatible
Herdr configuration. A setup failure fails activation rather than reporting a
successful refresh. `install.sh` also runs the same idempotent setup for bootstrap.

For a pinned refresh without updating dependencies, run
`sudo darwin-rebuild switch --flake ~/dotfiles/nix/.config/nix#mac`; it performs
the same automatic setup. To review settings changes without applying them, run
`bash agents/.config/agent-setup/apply.sh --repo "$HOME/dotfiles" --integrations`.

Production Herdr uses `nix/.config/nix/herdr-package.nix`, the same package as the
preview: pane footer, popup titles, and preserved launch flags on restore. The
package is guarded to Herdr 0.9.0 and runs the nine targeted Rust tests. Build just
the binary with `nix build ./nix/.config/nix#herdr`. `nixr` also updates flake inputs and may select a newer
Herdr version that needs its patches reviewed.

Once active work is finished, run `herdr server stop`, then reopen `herdr` to use
the new binary. Stopping a server terminates its pane processes; the declared
restore settings preserve sessions and their saved launch flags. Setup never
stops the server for you. Footer preferences live in `[ui.pane_footer]` in
`herdr/.config/herdr/config.toml`; prefix+r reloads presentation changes.

`install.sh` runs this same setup before the other Stow packages. The flake declares Stow, jq, dasel 3+, fzf and herdr; peon-ping is declared through its Homebrew integration. Apply the flake first. Scripts use Bash and macOS utilities, with no language-package installation or downloads during setup.

All owned configuration sources use TOML, including Claude's keybindings and theme. Dasel converts TOML to native JSON where Claude or Peon requires it, and converts Codex's merged settings back to TOML. Generated backup manifests and runtime state use JSON; they are not configuration declarations. Existing `jq` resolved to Apple's signed `/usr/bin/jq`; the explicit flake entry makes it a declared Nix dependency on fresh machines.

The apply command refuses a running server/CLI protocol mismatch before changing agent settings. During implementation the installed CLI was 0.9.0 while the production server was 0.8.2. Do not reload the new settings into that older server. Finish or preserve active work before updating the server; stopping it terminates its pane processes. This setup never stops the production server automatically.

Each apply that changes files prints a rollback manifest. Restore it with:

```sh
bash agents/.config/agent-setup/apply.sh --repo "$PWD" --rollback /path/printed/by/apply/manifest.json
```

Rollback restores owned files and the plugin registry; reload herdr afterward. It does not restart agents or revert running processes. Backups contain the original local settings and are kept under `~/.local/state/agent-setup/backups`, outside Git.

## Change preferences

| Preference | Source |
| --- | --- |
| Shared working agreement | `agents/.agents/AGENTS.md` |
| Portable skills | `agents/.agents/skills/` |
| Default agent and declared herdr integrations | `herdr/.config/herdr/plugins/config/agents/config.toml` |
| Claude preferences | `agents/.config/agent-setup/claude.toml` |
| Codex preferences | `agents/.config/agent-setup/codex.toml` |
| Peon event-delivery preferences | `agents/.config/agent-setup/peon.toml` |
| Claude keybindings and theme | `agents/.config/agent-setup/claude-{keybindings,theme}.toml` |
| Claude statusline and output style | `claude/.claude/` |

Settings fragments are merged; unrelated live settings survive. Removing a previously owned preference removes it only when its live value still equals the old managed value. Protected permission/trust fields are rejected and checked for preservation, except Codex's explicitly managed approval policy, reviewer and sandbox mode. Native integration installers retain their own hook entries.

Codex uses `on-request` approvals with `auto_review`, a `workspace-write` sandbox and `sandbox_workspace_write.network_access = false`. Eligible escalations go to an automatic reviewer; a rejection can still interrupt unattended work. This does not grant full access or blanket approval for Python or shell scripts. Existing trust records and additional writable roots remain local and unchanged. These settings take effect after applying the fragment and starting a new Codex session; managed policies or launch overrides can take precedence.

The default agent is Codex for this trial. Claude's pane entrypoint retains `--dangerously-skip-permissions`. Codex receives no translated bypass option. Claude forks retain the existing transcript-based permission-mode lookup.

## Controls

| Key | Action |
| --- | --- |
| prefix + Shift+C | New tab with configured default agent |
| Ctrl+Shift+C | New split with configured default agent |
| prefix + Alt+C | Choose Claude or Codex for a new tab |
| prefix + F / Shift+F | Fork focused session into pane / tab |
| prefix + A | Pick any running agent |
| Ctrl+Shift+I | Jump to agent needing attention |
| prefix + Alt+M | Toggle Peon sounds |
| Ctrl+G in either agent | External editor (`EDITOR=nvim`) |
| Ctrl+O in either agent | Native transcript view |

Claude's teammate preview moves to Alt+O. Ctrl+Shift+Minus stays herdr split; Claude undo retains Ctrl+Underscore. Shift+Up/Down stay workspace navigation; Claude's other message-selector top/bottom shortcuts remain. Specialized team/task/mode controls retain native semantics.

Both agents use Herdr's themed per-pane footer: directory, branch, access badge,
model and effort, context used, and reported usage limits. Codex keeps its native
Catppuccin syntax theme; its duplicate native statusline is disabled. Claude's
status callback feeds the collector without printing another line. Startup quota
data for Codex comes from read-only app-server requests before its first prompt.

Fork shortcuts also work while only the herdr package is Stowed: they resolve the shared helper from this checkout. Older Claude processes can use their exact PID/session registration. Codex processes started before the herdr integration was installed need to be resumed in a new CLI process to register their session identity; the fork command never guesses with `--last`.

## Peon

Only the herdr `peon` plugin emits completion and needs-input events. Apply removes Peon entries from Claude and Codex hook configurations and removes a legacy Peon `notify` callback if present. It retains non-Peon hooks, including native herdr session-identity hooks.

The bridge uses plugin events, with no background listener. It reads the current agent and sequence, rejects stale/repeated transitions, and serializes state updates. Completion uses Peon's `Notification/idle_prompt` route to avoid its global five-second Stop debounce. Herdr performs deduplication, so Peon's repeated-idle suppression is disabled. Peon's pack selection, volume and mute still apply; closely overlapping sounds can follow Peon's native playback interruption behavior.

Peon's installed data stays at its existing `~/.claude/hooks/peon-ping` location for CLI/package compatibility. That path no longer implies a Claude event source. The old tmux wrapper files are retained as existing files but are not registered by this setup.

Click handling stores server generation, terminal identity and provider session identity. It resolves the current pane at click time, rejecting exited/replaced sessions and old server generations. For Ghostty, it briefly marks the current herdr client's outer title, selects the matching surface and then returns title ownership to herdr. If no matching surface is found it raises Ghostty without guessing a tab. A detached server cannot raise an absent client. Notification delivery is intentionally conservative: the bridge does not suppress focused-pane banners based on ambiguous terminal/cwd heuristics.

## Intentional differences

- Models, reasoning effort, permission systems, queuing/planning, collaboration, native rendering, memory and remote-access features remain separate.
- Claude frontend-design and language-server plugins remain enabled through its preference fragment. Native provider plugins are not converted to another provider's packaging format.
- Open Design's existing MCP registration includes application-managed sidecar IPC/bootstrap state. It remains local instead of copying stale runtime paths into Codex. Set up Codex through Open Design's supported integration when needed.
- Council remains Claude-specific and is tracked in the Claude package. The shared `from-zero` skill creates AGENTS.md with a Claude compatibility link for new projects.
- Installed provider/third-party plugin caches and credentials are not copied into dotfiles.

## Voice

Claude's native voice is preserved. For Codex CLI, enable macOS Dictation under System Settings > Keyboard > Dictation, select a free shortcut, and dictate into the composer. Review the text before submitting. This needs a real microphone/terminal test; no unverified macOS defaults or microphone permissions are written by setup.

Codex's `realtime_conversation` feature was marked under development by the installed CLI and is not enabled in the baseline. Desktop voice is a separate native feature, dependent on account/rollout availability.

## Verification

```sh
bash tests/agent-setup.sh
bash tests/integration-herdr.sh
HERDR_CONFIG_PATH="$PWD/herdr/.config/herdr/config.toml" herdr config check
```

The integration test starts and stops only its own temporary server. It uses the real Peon engine and installed sound pack, replacing audio/banner output programs with file recorders. It submits no model prompts. It requires access to local sockets and the installed executables.

Verified during implementation:

- Temporary-home Stow installation, second-apply idempotence and rollback.
- Native settings merge and preservation of permissions/unrelated settings.
- Selective removal of Peon hooks while retaining other handlers.
- Exact provider/session fork command construction and clean failure before pane creation.
- Transition deduplication, independent pane identities and stale-server click rejection.
- Both plugins accepted by herdr 0.9.0 without manifest warnings.
- Real herdr working/completion/blocked events produced exactly three Peon sound/banner calls; repeated blocked state produced no extra call.
- Codex app-server accepted the native preference fragment; Ghostty AppleScript compiled.

Still requires an interactive pass after activation: real banner/audio presentation; click focus across Ghostty windows/tabs and other foreground apps; dictation; native agent launch/fork/restore; common keyboard gestures. The production server has not been stopped or reloaded for these checks.

# Per-pane agent footer: source investigation

Status: the verified Herdr v0.9.0 patch set is wired into the production Nix package.
System activation and server restart remain user-controlled. See `agent-setup.md`
for rollout commands. The notes below also preserve the preview investigation.

## Live preview (2026-09-10)

Attach with `bash /Users/papu/dotfiles/scripts/herdr-footer-demo.sh attach`.
The updated preview uses a separate `-v5` server directory;
the previous preview sessions remain running. Select `Live footer preview`.
The original synthetic shell panes were removed. Real Claude and Codex sessions
are open; the V5 Codex footer was verified before submitting any prompt.
Missing measurements are omitted; percentages are used, not remaining.

Directory is green, branch blue, and elevated-access badges red on the left.
Model and effort are purple on the right, immediately before usage, without a
redundant CLI name. Usage is green through 80%, amber above 80% through 95%,
and red above 95%. The model is omitted if it cannot fit beside the usage fields;
on narrower panes the lowest-priority usage fields are dropped without overlap.

The preview uses the shared theme and built-in keybindings (`ctrl+\\`, then `d`
to detach). Custom plugin shortcuts are not copied into this isolated instance.
Claude's native status callback publishes metrics without printing a duplicate
line; Codex's native status line is disabled only for the preview launch.

Implementation: `nix/.config/nix/patches/herdr-pane-footer.patch`, built through
`nix/.config/nix/footer-preview.nix`; collectors and launchers live under
`herdr/.config/herdr/footer/`. The preview plugin is deliberately outside the
production plugin registration directory. `scripts/herdr-footer-demo.sh start`
configures the preview and opens real agents; `live` opens another pair.

Validation: release build, six Rust footer tests (geometry, Unicode overflow,
missing values/colors, configuration), jq metric and startup fixtures, live session identity and metadata
updates, and attached terminal rendering at narrow and wide sizes. Broader mouse,
and 15-pane performance verification remains before production rollout. Native
Claude and Codex permission flags were verified across repeated server restores.

The five-hour and weekly figures measure the account, not the session, so the
newest reading any session observed is what every pane of that provider shows.
Without this an idle pane reported its own last observation, which drifted by
nine points over a day. The collector seeds those readings from every session's
sample file at startup, and drops a window whose reset time has passed rather
than presenting a rolled-over percentage as current. Claude has no read-only
usage endpoint, so its figures still advance only when some session calls the
API. Codex does, and a pane reads it every two minutes through the same
read-only `account/rateLimits/read` request used at startup, so an idle Codex
pane no longer waits for a logged turn.

Codex uses the unmodified Nixpkgs package and the rollout fallback.
Idle permission and context changes may wait for another logged turn. The
collector still accepts live metadata from existing patched processes after
checking process identity, socket, and file age.

Each pane has an independent collector worker that checks for changes every
250 ms. Socket requests and JSON reads stay in the collector process; Git results
are cached for five seconds. Changed values publish immediately, while unchanged
values renew their 15-second metadata lease every five seconds. A slow startup
quota query cannot delay another pane. Unknown values clear the corresponding
field. Rollout fallback retains only parsed metadata and an incomplete line in
memory, and resets when the session or log file changes.

No sampling failure ends the collector. A worker and the supervisor log the
error and retry, doubling the interval to a five-second ceiling until the pane
recovers, so a departing server cannot drive a logging loop. Server refusals are
logged without a traceback because a closing pane produces them routinely, and a
terminal listed before its agent is identified is skipped rather than treated as
malformed. Workers for departed terminals are dropped, and `SIGTERM` stops the
collector without killing an in-flight publication. Startup also sweeps lock
files from retired socket generations that no collector still holds.

Presentation is configured in `herdr/.config/herdr/pane-footer.toml`: field order
and side, colors, labels, separator, enablement, and percentage thresholds.
Context percentages represent **used** context; a fresh session shows `ctx 0%`.
Permission badges use `access_color` (yellow); `[bypass]` uses `critical_color`
(red). Full access with approvals remains distinct from bypass. Claude's native
status callback still supplies its metrics and reads the latest transcript
`permissionMode`; the collector does not invent permissions when none are known.

Codex retains its native input colors, context indicator, and keypress hints.
The local Codex source patch was removed because rebuilding on frequent upgrades
made system updates too slow.

Herdr's patched release passed all 11 package checks and the isolated integration
suite. Collector and startup fixtures passed. Earlier patched-Codex validation
no longer describes the installed package.

## Decision

### Agent colors (2026-09-10)

The automation environment exported `NO_COLOR=1`, which the preview server
and its agents inherited. This suppressed the agents' ANSI colors while herdr's
own footer remained colored. The preview startup script now unsets `NO_COLOR`,
and the agent launcher also unsets it for servers that were already running.
Both test conversations were resumed with the corrected environment. Verified
RGB foreground colors in Claude's terminal snapshot, and colored foreground
accents and the prompt background in Codex's snapshot. No Rust rebuild or
production configuration change was necessary.

### Blank Claude pane investigation (2026-09-10)

Compared stock herdr 0.9.0 with the footer build using disposable Claude 2.1.267
sessions, the same prompt, and the user's fullscreen Claude configuration.
Both preserved the banner, prompt, and response across resize from 200×40 to
380×70, detach/reattach, shrink/grow via 80×24, and narrow split panes. The
footer build consistently reserved one additional row.

Ctrl+L reproduced the screenshot's empty conversation area in both builds.
Ctrl+O revealed the original transcript in both probes and in the user's
existing preview pane. The original preview was left in transcript view so its
content is visible; Ctrl+O returns to the normal prompt. No renderer change was
made: the original triggering action has not been confirmed, and these checks
do not prove that every TUI interaction is correct.

[Claude's fullscreen documentation](https://code.claude.com/docs/en/fullscreen#clear-the-conversation)
explains that, since 2.1.260, Ctrl+L clears the visible screen while retaining
conversation history. Earlier versions used it to redraw. PgUp/mouse scrolling
or transcript view can reveal earlier messages. Do not prescribe Ctrl+L as a
harmless redraw-only diagnostic for this Claude version.

Add one herdr-owned row underneath each Claude/Codex terminal, including unfocused panes. Do not use the shared tab bar, draw into the agent's terminal buffer, or patch the agents. Keep both native status lines during verification, then disable redundant native output only after the collectors are reliable.

Example (all percentages used):

```text
feature/login · claude · sonnet high             ctx 24% · 5h 31% · week 42%
dotfiles · codex · astra medium                   ctx 6% · week 12%
```

Each line belongs to its own pane. Worktree/branch and agent/model/effort are on the left; usage is right-aligned inside that pane. The first version reserves one row only. No separate divider row is required.

## Verified source paths

Upstream source: https://github.com/herdrdev/herdr/tree/v0.9.0

- `src/ui/panes.rs`: `resize_tab_panes`, `compute_pane_infos_for_tab`, and `render_panes` compute terminal geometry, resize PTYs, and render pane chrome. Both zoomed and split branches must reserve the footer row before calculating the scrollbar gutter.
- `src/layout.rs`: `PaneInfo` distinguishes the whole pane rectangle from `inner_rect`. Use a shared geometry helper; do not reduce height only in the renderer.
- `src/app/agent_resume.rs`: restored/deferred agent processes have an additional geometry path. Their initial PTY dimensions must agree with normal rendering.
- `src/ui/tab_surface.rs`, `src/server/client_shell.rs`, and `src/server/headless/retained_surface.rs`: cursor, hyperlinks, graphics surfaces, and retained frame placement depend on the inner rectangle. Verify the footer is composed as herdr chrome and survives incremental terminal updates.
- `src/client/shell/mouse.rs`: terminal mouse delivery checks the terminal inner rectangle. Footer clicks should focus the pane without being forwarded to the agent; dragging a terminal selection and wheel handling also need coverage.
- `src/ui/sidebar/tokens.rs` and `src/config/sidebar/{rules.rs,..}`: existing token resolution and conditional colors provide reusable components. Extract common pieces rather than creating a second rule language.
- `src/terminal/state.rs`, `src/terminal/metadata.rs`, `src/metadata_tokens.rs`: per-terminal metadata already supports custom tokens, expiry and report sequencing.

## Data contract

Use the existing `pane.report_metadata` API. Keep token values structured as individual strings, not a precolored ANSI line. Numeric usage tokens contain bare percentages, with labels and `%` added by the renderer; herdr's numeric style rules require a fully numeric value.

Proposed namespace: `footer_model`, `footer_effort`, `footer_worktree`, `footer_branch`, `footer_ctx`, `footer_5h`, `footer_week`, `footer_session`, `footer_measured_at`. Names fit the existing 32-character limit and one update fits the 16-token report limit.

Key cache entries by server generation, stable terminal identity, provider and exact session identity. Resolve the current pane ID when publishing so moved panes keep the correct data. Use a stable reporter source and monotonic sequence. Do not create a new metadata source per update: herdr bounds the number of sequenced sources per terminal.

Important: `agent` and `applies_to_source` guards do not protect custom token patches. Before publishing, validate the current terminal/session mapping. Explicitly clear metrics on replacement or exit; use a short TTL as a fallback. Collector liveness and measurement freshness are separate: an idle session may legitimately have an older quota observation. Missing fields are omitted, never replaced with zero; preserve the measurement timestamp instead of making old observations appear newly measured.

Claude: extend the existing status-line callback to publish its documented model, effort, context used and quota used values while preserving current native rendering. The installed Claude version supports the documented quota fields, but some fields are absent before a response or for certain account types.

Codex: use the exact session identity supplied by its SessionStart integration to select the session log. Local inspection confirmed `turn_context` model/effort/cwd and `token_count` token usage, model context window and quota used percentages. Classify quota windows by duration: a sampled primary window was weekly, not five-hour. Logs are internal and require defensive parsing, incremental reads, partial-record handling and version fixtures. Do not scrape screen text or assume an unrelated app-server process observes the live CLI. Matching Codex's own context percentage, including its reserved context calculation, remains to be verified; do not silently replace it with lifetime-token usage divided by the context window.

## Configuration and behavior

Add a proposed `[ui.pane_footer]` TOML section (not supported by stock herdr yet) for enablement, included agents, left/right tokens, display labels, normal colors, thresholds and overflow priorities. Reuse existing token rules where possible.

Default behavior:

- Enabled for Claude and Codex, in all visible agent panes; no footer for shells or plugin picker overlays.
- Context and quotas show used percentage. Normal values neutral/green, amber above 80% used, red above 95% used; thresholds configurable.
- Reserve stable height while an eligible agent is running, even if telemetry has not arrived. Avoid resizing its terminal on every measurement or TTL expiry.
- Allocate by terminal display-cell width, including Unicode. Shorten the worktree path and hide lower-priority identity fields before metrics; then drop weekly and five-hour fields as needed, keeping context longest. Never overlap left and right sections.
- A pane too short to retain a usable terminal hides the footer.
- Focus may adjust background/border styling, but does not determine which sessions receive updates.

## Delivery and verification

1. Implement layout and renderer with synthetic independent metadata for two panes; build a patched herdr through the pinned Nix package and verify in an isolated server.
2. Add collectors using Bash/jq and the declared Nix tools; no language package installs. Validate current session identity and expiry handling before publishing.
3. Exercise real Claude and Codex sessions in an isolated workspace; compare readings with native displays before hiding native footers.
4. Add the patch and activation wiring to the declarative setup. Building may be automatic; replacing/restarting the production herdr server must not silently terminate active panes.

Required tests: split horizontally/vertically; zoom/unzoom; borders on/off; narrow/short panes; Unicode paths; mouse clicks and drag selections at the footer boundary; scrolling; alternate screen; cursor placement; restore dimensions; graphics/retained redraw; independent sessions in the same repository; move/replace/exit; missing/expired/out-of-order metadata; unavailable quota windows; context compaction; disabled-feature behavior.

Still unverified: complete patched build, collector implementation, exact Codex context-percentage parity, visual rendering and remote/direct-attach behavior. No production server has been restarted for this investigation.

## Editable footer configuration

Edit `herdr/.config/herdr/pane-footer.toml`, then run:

```sh
bash ~/dotfiles/scripts/herdr-footer-demo.sh reload
```

The script merges this declaration into the isolated preview's native herdr
configuration, validates it, and reloads the running server. Invalid config
leaves the previously generated config in place. No Rust rebuild or agent
restart is needed for field visibility/order/side, labels, separator, palette
or hex colors, background, enablement, or the warning/critical percentages.
`model` and `effort` are separate fields. Missing fields are always omitted.

Supported fields: `access`, `directory`, `branch`, `model`, `effort`, `context`,
`five_hour`, `weekly`. Each side allows at most eight items; empty arrays hide
that side. Tokens must be distinct within each side. On narrow panes, the right
side has priority; model/effort groups are dropped first, then rightmost items,
and the left side is clipped.
This is presentation configuration: new telemetry sources or new behaviors
still require implementation work. The current preview remains separate from
production. Both now build the same patch set from `herdr-package.nix`.

Verified live reload by changing the model color to `#11aa22`, the context
label to `CTX`, and the right-side order to weekly/model/context. Both agent
footers updated in the attached TUI. The Claude process PID stayed unchanged,
agent session/terminal identities stayed unchanged, and the Nix derivation
path stayed unchanged. An invalid color was rejected without replacing the
active config. Restored the user's default layout and colors afterward.

## Literal groups and separate effort

Model and effort are independent fields, with `model_color` and `effort_color`.
Outer items use the global separator. Inner arrays concatenate tokens and literal
text directly:

```toml
separator = " · "
right = [["model", " ", "effort"], "context", "five_hour", "weekly"]
```

This renders `model effort · ctx …`. Every token retains its own color; literal
text uses `separator_color`. Removing `effort` hides it independently. Missing
tokens are omitted, and a group with no available token data is omitted entirely.
Otherwise literals remain exactly as written, including whitespace around a
missing token. Literal-only groups render their text. Groups work on either side,
allow at most sixteen elements, and cannot contain further groups. Literal text
must be printable and at most 32 bytes. Separators appear only between visible
outer items. Narrow panes drop whole groups before clipping remaining text.
The collector temporarily also publishes the combined legacy model token for
older preview servers; the new renderer consumes separate model-name and effort
metadata.

The V4 preview combines the footer, popup-title, and preserved-launch-flags
patches. Its checked Nix build passed five footer tests, two popup-title tests,
and two launch-flags tests. Live Claude and Codex sessions verified separate
model/effort telemetry and nested-group rendering. Changing the inner literal
to ` / ` and `effort_color` to `peach` updated both footers through reload;
the default space and mauve color were restored afterward.

## Startup, popups, and permission restore verification

The installed Codex 0.153.4 defers SessionStart hooks until a turn begins
(`core/src/session/turn.rs` calls `run_pending_session_start_hooks`). This is why
the old collector required a prompt. V5 displays startup model, effort, branch,
and a freshly fetched quota before any prompt or reported session identity.
`tests/herdr-footer-startup.sh` verifies the read-only protocol and missing-limit
handling with a local fixture; no network or model request is needed for that test.

The preview generator now includes custom popup and shell bindings, the declared
session-restore settings, and pane-history settings. Plugin-action bindings are
still excluded because the preview does not register the production plugins.
Verified prefix+g and prefix+h render `Lazygit` and `GitHub Dashboard` titles.

Preview agents now launch directly with native argv. Generated plugin manifests
resolve callback paths to absolute paths: neither permission flags nor callback
paths depend on a Bash wrapper or ephemeral plugin environment after restore.
The footer collector lock is scoped to the socket generation, preventing a
departing collector from blocking startup after a rapid server restart.

In `/tmp/herdr-footer-verify`, Claude's `--dangerously-skip-permissions` and Codex's
`--dangerously-bypass-approvals-and-sandbox` survived two full stop/start cycles
with unchanged session IDs. Actual process argv retained the flags; Claude's TUI
showed bypass enabled and Codex `/status` showed Full Access. Both footers resumed
with `[bypass]`, and the collector restarted automatically after the lock fix.
The user's active preview and production sessions were not restarted.

Production configuration is now split: stock-compatible `config.toml` and
patch-only `pane-footer.toml`. The patched loader reads the extension beside the
selected base file; no merged configuration is written back to disk. Verified
stock validation with the extension present, patched startup, successful reload,
failed reload for an unknown extension key, and recovery after fixing that key.
The base file remained byte-identical. Ten targeted Rust tests passed in the
combined build, including the extension loader regression test.

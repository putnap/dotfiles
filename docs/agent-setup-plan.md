# Claude / Codex setup implementation plan

Status: implementation is in dotfiles. See [agent-setup.md](agent-setup.md) for actual commands, completed checks and activation limitations. The user simplified scope: herdr is the sole Peon event source; native notification adapters are removed rather than retained.

Dependency decision: owned configuration is TOML; automation is Bash with jq and dasel 3 supplied by the Nix flake. Native JSON files are generated where required by Claude/Peon. No Python, Node modules, or package-manager bootstrap is used by this setup. jq was found at Apple's `/usr/bin/jq`, so it is now explicitly declared in Nix.

Follow-up authorization: the user subsequently requested unattended Codex operation with `approval_policy = "on-request"`, `approvals_reviewer = "auto_review"`, `sandbox_mode = "workspace-write"`, and `sandbox_workspace_write.network_access = false`. These four managed settings supersede this plan's permission exclusion for Codex only. Claude permissions, trust records and launch flags remain outside that change. See `agent-setup.md` for activation limitations.

## Scope and boundaries

- SHARE: working agreement, portable skills, shell/editor tools, herdr navigation, reproducible setup.
- TRANSLATE: common keyboard actions, useful status information, MCP registrations, notification outcomes.
- SPLIT: models/effort, native plugins, agent collaboration, planning/queuing semantics, voice implementations, rendering, memory and session formats.
- LOCAL: credentials, trust records, histories, generated memory, onboarding state and caches.
- DEFER: all permission-policy unification. Preserve existing permission rules, sandbox/approval settings, launch flags and source-session permission behavior. This includes Claude's current herdr bypass flag. Do not introduce a Codex counterpart to it. Notification handling of an approval event is in scope; changing whether approval is required is not.

Existing working-tree changes must be preserved. Capture the starting diff before implementation; do not overwrite unrelated edits.

## Verified starting points

- Installed versions inspected: herdr 0.9.0, codex-cli 0.153.4, peon-ping 2.37.0.
- Herdr integration status reported Claude outdated and Codex not installed.
- Herdr's API schema exposes `AgentInfo.agent_session` with `agent`, `kind`, `value` and `source`. Session kinds are `id` or `path`. Use this instead of guessing the most recent session.
- Herdr's subscription schema exposes `pane.agent_status_changed`; agent records include `state_change_seq`. Plugin event naming/availability must be proven separately before choosing a manifest hook over a socket subscriber.
- Peon already ships `adapters/codex.sh`, supporting native lifecycle hooks and legacy notify callbacks. Do not register both delivery paths for the same event.
- No herdr handling was found in the installed peon engine or notification script.
- Peon issue 574 remains open in the fetched issue data. It describes swallowed pane OSC notifications and incomplete click focus. The maintainer also warns that the inherited terminal identity can become stale after reattachment.

Sources: [herdr plugin documentation](https://herdr.dev/docs/plugins), [peon issue 574 and discussion](https://github.com/PeonPing/peon-ping/issues/574). Local executable help, schemas and installed adapter source were also inspected.

## 1. Prove notification transport before migration

Create a small local herdr integration prototype using recorded event fixtures and an isolated test session. Prefer plugin event hooks if the installed version delivers suitable status events; otherwise use a supervised socket subscriber. Do not run a persistent listener as an unsupervised one-shot startup hook.

Preferred architecture:

```text
Agents inside herdr -> herdr state events -> notification bridge
                                           |-> peon sound engine
                                           |-> one banner delivery path

No native Claude/Codex notification adapters are installed or retained.
```

Herdr is the sole source of completion/attention events. Keep native herdr agent integrations for session identity and restoration.

Bridge requirements:

- Map a new `done` transition to completion and `blocked` to generic input required. Do not claim blocked always means a permission prompt.
- Ignore initial idle/unknown state, focus acknowledgements and repeated observations. Do not fabricate tool failures, resource limits, prompt submissions or subagent events from terminal state.
- Deduplicate per herdr server generation, pane and transition sequence. Handle simultaneous agents, restarts, out-of-order callbacks and pane destruction. Do not replay historical completions on reconnect.
- Retain peon's actual playback behavior where supported: pack selection, rotation, mute and volume. Verify an invocation/configuration that suppresses peon's extra banners and terminal-title writes without preserving a standalone adapter path. Do not use `peon preview` for event playback; it plays a category's sounds rather than one event.
- Prefer herdr's native pane-targeted notification delivery if it meets the desktop click requirements. Otherwise use one host-side peon/system notification adapter with a stable target. Never send notification OSC into a herdr child PTY.
- Notification targets identify the herdr server/socket and exact pane, not just cwd or tab index. Resolve the pane's current tab/workspace on click so moving a pane does not stale the target.
- Clicking from another application must focus both the inner pane and the outer Ghostty window/tab hosting the attached herdr client. Resolve the current client/host at click time. Handle a missing pane or detached client without focusing an unrelated session.
- Suppress only when the target is actually visible and the host application is foreground. If visibility cannot be established, prefer delivering the notification.
- After the bridge passes, gate only native peon attention/completion hooks inside herdr. Remove native Claude/Codex Peon hooks. Disable duplicate herdr sound playback when the bridge owns sound.
- Do not retain native Peon adapter features outside herdr. Document which detailed lifecycle sounds are unavailable through herdr instead of inventing equivalents.

If herdr state detection misses important events, fix or report that integration gap. Do not introduce a second native-adapter notification path.

## 2. Voice

Treat prompt dictation and a live spoken conversation as separate features.

For prompt dictation in the CLI, first test macOS Dictation in Ghostty -> herdr -> Codex. Enable it through System Settings > Keyboard > Dictation, choose a non-conflicting shortcut, and dictate into an editable prompt. Text must remain available for review before submission. Validate punctuation, multiline text, cancellation, existing draft preservation and focus switching. The actual terminal input path must be tested; generic macOS support is not proof that this stack handles it correctly.

If that fails, assess a dedicated dictation tool with a preview/clipboard workflow as a separate small choice. Do not build a transcription service or select a paid service without need.

Keep Claude's native voice enabled. Native desktop voice for Codex is also a separate option: current OpenAI documentation describes Start voice chat in supported desktop tasks, microphone permission and a configurable Voice chat hotkey, subject to account/rollout availability. This does not establish an equivalent stable CLI interface.

The installed CLI lists `realtime_conversation` as under development and disabled. An optional isolated trial can use `codex --enable realtime_conversation`; first confirm the installed TUI exposes usable controls and the account supports it. This flag alone does not prove working dictation or full voice. Do not persist it in the baseline before testing.

Sources: [OpenAI desktop voice](https://learn.chatgpt.com/docs/features/voice), [Apple Dictation](https://support.apple.com/en-gb/guide/mac-help/mh40584/26/mac/26).

## 3. Shared instructions and skills

- Store one portable working agreement in the `agents` Stow package, exposed as `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.
- Consolidate portable concise-output preferences without changing the user's autonomy/permission policy during this migration.
- Store personal portable skills at `~/.agents/skills`; link individual skills into Claude. Avoid duplicate Codex discovery paths.
- Capture all supporting skill resources. Audit hardcoded tool names, CLAUDE.md scaffolding, slash-command semantics and orchestration dependencies before declaring a skill portable.
- Preserve provider-specific skills and bundled/plugin-managed skills in their native locations. Track third-party source/revision or vendor a reviewed version with license/provenance.
- Keep project instructions in their repositories; optionally declare Codex's CLAUDE.md fallback for existing projects.

## 4. Declarative settings and installation

- Stow owned instruction files, skills, scripts and native keybinding files. Do not stow whole runtime directories.
- Keep recognizable Claude JSON and Codex TOML preference fragments. Merge only explicitly owned fields into mutable live settings; preserve unknown fields and exclude permissions/trust from ownership.
- Track plugin/integration installation intent. Use herdr's bundled installers as the user, not root; preserve unrelated hook registrations. Do not run a full system rebuild just to apply agent preferences.
- Use an apply command with dry-run diff, backup, validation, idempotence and rollback. Track prior ownership so removing a managed entry removes only that entry. Merge hook arrays by managed identity, not blind concatenation.
- Keep secrets, authentication and generated state out of Git. MCP declarations may refer to secret environment-variable names, not values.
- Validate owned settings against installed versions. Report unsupported fields instead of silently ignoring them.

## 5. Agent-neutral herdr controls

- Add separate Claude and Codex plugin pane entrypoints; retain direct program launch.
- Declare the default agent and integration list in the local agents plugin configuration. Herdr 0.9.0 does not provide native main-config keys for these; do not disguise custom values as built-in options.
- Start with Codex as the default for this trial, with a chooser for a one-off launch.
- Keep pane/tab launch keys, picker, attention navigation and worktree layout.
- Fork using focused pane's reported provider and exact session reference. Use provider-specific native commands, preserve current source-session permission handling, and reject missing/unsupported identity before creating an empty pane. Never use `--last` as focused-session identification.
- Verify restoration with current native integrations. Do not translate transcripts between agents.

## 6. Common interaction and provider strengths

- Match common actions through native keymaps: submit/newline, cancel, history, external editor and image paste where semantics agree.
- Audit herdr/agent conflicts for Ctrl+Shift+Minus, Ctrl+Shift+O and Shift+Up/Down. Record actual delivery in Ghostty rather than assuming which layer wins.
- Preserve native task/team controls, queuing/steering, mode cycling, model selection, collaboration, remote access and voice features.
- Match useful status information and color family. Use native rendering; do not port Claude's statusline input contract into Codex.
- Share external service access only where suitable. Keep native LSP/design plugins and Codex connectors independently enabled; avoid duplicate registration of the same service.
- Keep model, effort, service tier, context handling, retention and memory provider-specific.

## Final implementation verification

| Area | Required evidence |
| --- | --- |
| Permission exclusion | Before/after semantic comparison proves rules, sandbox/approval fields, trust and launch flags unchanged. |
| Existing work | Starting diff recorded; unrelated user edits preserved. |
| Setup | Dry run shows owned changes; second apply is a no-op; rollback restores prior files; no credentials/state enter Git. |
| Integrations | Status shows current Claude/Codex integrations; unrelated hooks survive; installers do not duplicate hooks. |
| Instructions/skills | Both agents report the intended global guidance and portable skills; supporting resources resolve; no duplicate skill entries. |
| Launch/fork | Both launch in the correct cwd; two sessions in one repo fork the selected pane's exact session; missing identity fails cleanly. |
| Restore | Disposable herdr session restores both provider conversations; production server is not restarted as a test. |
| Notifications | Exactly one intended sound/banner for done/blocked; no duplicates from native hooks, repeated snapshots, reconnect or focus acknowledgement. |
| Concurrent events | Two panes completing together keep separate identities and both notify; rapid state changes do not replay stale transitions. |
| Focus | Same/different workspace, split pane, another Ghostty tab/window, another foreground app, moved/closed pane, detach/reattach all behave correctly or fail safely. |
| Herdr-only | Native Peon hooks are removed; native herdr session-identity hooks remain. |
| Peon controls | Mute, volume and pack selection/rotation remain effective; shared path never changes agent terminal titles. |
| Voice | Real microphone test inserts reviewable text into the intended composer, preserves draft and does not submit automatically; GUI permissions are verified interactively. |
| Keyboard/UI | Common chords work in both tools without breaking herdr gestures or native specialized controls. |
| Native strengths | Existing Claude plugins/voice/remote settings and Codex native capabilities remain usable. |

Automated checks cover configuration merging, shell syntax, TOML/JSON validation, event mapping/deduplication and argument/identity handling. Live audio, microphone and window-focus checks require an interactive pass; report them separately from automated results.

Implementation readiness gates: prove herdr event delivery, choose and verify peon playback/banner routing, and validate the CLI dictation path. If a gate fails, use the documented narrower fallback and record the difference before migrating live settings.

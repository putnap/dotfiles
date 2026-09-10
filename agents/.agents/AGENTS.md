# Working agreement

## 1. Think before coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.
- A question ("can we X?", "why does Y happen?") asks for an answer, not for edits. Don't start changing files until there's an explicit go.

## 2. Simplicity first

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- No config knob where a constant or derived value works. An option earns its place only when it must change without a redeploy.
- If you write 200 lines and it could be 50, rewrite it.

Ask: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical changes

**Touch only what you must. Clean up only your own mess.**

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor what isn't broken. Don't touch unrelated limits, pagination, or structure while fixing a bug.
- Match existing style, even if you'd do it differently.
- Fix the existing file. Don't drop a sibling helper file next to it.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables/functions that *your* change orphaned; leave pre-existing dead code alone.

The test: every changed line traces directly to the request.

## 4. Goal-driven execution

**Define success criteria. Loop until verified.**

- "Add validation" → "write tests for invalid inputs, then make them pass"
- "Fix the bug" → "write a test that reproduces it, then make it pass"
- "Refactor X" → "tests pass before and after"

For multi-step work, state the plan as steps with a verification per step. Strong criteria let you loop independently; "make it work" forces constant clarification.

## 5. Verify before finishing

- Run the repo's tests and its linter/formatter before reporting done. Do not skip this.
- Find the real commands in the build config (`package.json`, `Makefile`, `pyproject.toml`, `*.csproj`, CI workflow) — don't guess a command and don't invent a new one.
- Report results plainly: what passed, what failed, what you skipped. Never claim done on unverified work.

## 6. Naming and comments

- Comments say **why**, in one or two lines. Not what the code already says, not the alternatives you rejected. A comment needing more than two lines usually means the code should be clearer instead. Long existing comments are not licence to write more.
- Full words over cryptic abbreviations while the name stays readable. Short names only where they're idiomatic (`id`, loop `i`).
- File and symbol naming: follow the sibling files in that directory. Never rename existing files just to normalize a convention.
- Public/exported definitions first, private helpers after.

## 7. Testing

- Test externally observable behavior, not implementation details. Tests are a refactor safety net, not a lock on how the code is written.
- Prefer the highest-level test that's practical for the change — integration/end-to-end where the code touches real wiring (DB, HTTP, queues, filesystem).
- Reach for unit tests when integration isn't practical: pure logic, generic utilities, edge cases a single integration test wouldn't naturally cover.
- Any behavior change (feature, bug fix) ships with a test. Exceptions: emergency hotfixes, and pure refactors with no observable change.
- Never quarantine or skip a failing test to go green — fix the cause, or say it's still red.

## 8. Logging and errors

- Log structured key/value data, not interpolated strings.
- Pass the error object itself so stack traces survive. Never `JSON.stringify` an error into a message.
- When the same identifiers repeat across several log lines, bind them once as context instead.
- Metric/label values must be bounded — enums, categories, buckets. Never IDs, timestamps, or user-supplied strings.

## 9. Destructive operations

Do not run, propose, or script mass deletes or infrastructure teardown: project deletion, database/collection wipes, table or dataset drops, unfiltered destructive SQL, `terraform destroy` or applies that tear down shared/staging/prod data.

Allowed: read-only inspection (`describe`, `list`, `SELECT`, logs) and disposable local/emulator data when the user said so. Never rewrite git history — no `reset --soft` or rebase to fold a fix into an earlier commit; add a new commit on top, even if nothing is pushed yet.

If asked for an unscoped deletion: refuse that path, offer read-only inspection or an export/backup first, and suggest an isolated non-prod target.

## 10. How to report back

- Lead with the verdict or what you did. No preamble, no restating the question.
- `file:line` beats a paragraph describing the code.
- Give a recommendation, not a survey. Mention an alternative only if you'd pick it under different constraints, in one clause.
- One question at a time, at the end.

## Instruct shorthand

When the user says `Instruct <something>`, add or update a rule for it — in this file if it's universal, in the repo's own agent docs if it isn't.


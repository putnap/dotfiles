---
name: from-zero
description: Scaffold a new app repo with the working method distilled from Longplay - seed AGENTS.md (the law, constitution, feature audit, rule rungs), one ci command with a promotable checks file, and the paper system (requirements with IDs, behaviour sheet, todo ledger). Use when starting an app from zero, or when a young repo has no working rules yet.
---

# From zero

Seed the machinery that turns incidents into rules. This installs scaffolding, not the app, and should take well under an hour. The full reference playbook, with the evidence behind every rule here: https://claude.ai/code/artifact/a91546e8-9859-44e1-a622-851f73a554ae

## 1. Ask the constitution

One clarification round using the available user-input mechanism, only for what the repo can't tell you:

- Who owns state and decisions (a daemon, a server, a core crate), and what only renders or asks?
- Which external services will it touch? Each will get an adapter and a protocol-faithful fake, but only when it's actually integrated.
- Stack, if not obvious. It decides the shape of the one command.

## 2. Write AGENTS.md from this template

For Claude compatibility, create CLAUDE.md as a symlink to AGENTS.md when neither file exists. Preserve existing project instruction files and their conventions.

Fill the blanks, delete what doesn't apply, keep it near 40 lines. Do not pre-install rules for incidents that haven't happened; a rule is only real the day it costs something.

```markdown
# <App> — working rules

## The law
Every question this app can be asked has exactly one place that answers it.
A second answer is the bug, even while both answers are still right. Each
rule below is this sentence applied somewhere; when a rule and the law seem
to disagree, the law wins.

## Before you report done
`<ci command>` — formatting, lints as errors, tests, and the structural
checks. One command, because a rule an agent has to remember to run is a
rule that does not hold. It reports any check it could not run rather than
passing quietly.

## Shape
- <Who owns state and decisions> decides. <What renders> asks; it never
  decides. A rule written in a renderer is a bug even while it works.
- Every side effect goes through <the recorded door>. That is what makes
  dry-run a property rather than a promise, and the journal is yesterday's
  behavior as data.
- One door per thing the app can be asked to do; every front end calls it.
  The door returns what happened and prints nothing.
- The first of anything is written concretely. The abstraction is built the
  day the second arrives: count the seams the first one cost (the list goes
  in the commit message), widen in one commit with no behavior change, and
  prove the shape with a fixture instance the core cannot tell from a real
  one. Never bolt the second onto the first's shape.

## When a feature comes in
1. Say it as one sentence about what the app does. An "and" means two
   features and two commits.
2. Name the questions it asks; for each, call what already answers it.
   Something that almost answers it is widened, never forked.
3. Find where one of those questions is already answered twice. That
   duplication is why the feature feels hard. Fix it first, in its own
   commit, with no behavior change.
4. Ask what fails to compile. If a new <source/screen/state> can be added
   and everything still builds, fix the shape before adding the thing.
5. Test it at the highest boundary it shows at. A test name is a sentence
   about what the app does, never the name of the function under test.
6. Add its line to docs/behaviour.md once it is confirmed.

## Rules that are checked, and rules that are not
1. The type system — illegal states do not compile.
2. `<ci command>` — broken loudly, once.
3. This file — prose, which decays silently.
The second time a rung-3 rule is broken it becomes a rung-2 check in
<checks file>; writing it down again is not a fix. A rule nobody can
imagine a check for is a taste, not a rule: said once, never repeated.
No rule outlives its feature.
```

## 3. Set up the one command

Same shape in any stack: format check, lints as errors, tests, then the structural checks file.

- Rust: an `xtask` crate; `ci` runs `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, then `checks::run()`.
- Node: a `ci` script chaining the formatter's check mode, lint with zero warnings allowed, tests, then `node scripts/checks.mjs`.
- Anything else: one entry point, same four stages.

The checks file starts nearly empty, with this header:

> Structural rules promoted from AGENTS.md after being broken twice.
> Dumb substring scans over source text are enough; the failure message
> states the rule and the fix direction, so the error teaches.

If the command cannot run one of its stages, it says so loudly instead of passing without it.

## 4. Seed the paper

Every document opens by defining what a line in it means and ties "done" to the one command.

- `docs/requirements.md` — items carry stable IDs (`ABC-01`). Commits, comments, and config names cite them forever.
- `docs/behaviour.md` — header: "Each line is a sentence somebody could read without knowing how the code is shaped, so a refactor that keeps all of them true changed nothing anybody can see. ✓ means a test exists at the named boundary; unchecked means check by hand."
- `docs/todo.md` — header: "A line is a gap between the requirements and the code. Checked means done and `<ci command>` passes." Sections: Build, Flagged not scheduled, Looked at not taken. Done items stay, rewritten as past-tense stories with their numbers. Rejections keep their reasons so nothing is re-litigated.

## 5. What not to build yet

- No adapters or fakes for services not yet integrated. When one arrives, its fake arrives in the same commit.
- No abstraction with one user. Part "Shape" above schedules its birthday.
- No rules beyond the template. The machinery catches incidents and turns each into a rule the day it happens.

When the app later becomes hard to change, that is /rearchitect, not more rules here.

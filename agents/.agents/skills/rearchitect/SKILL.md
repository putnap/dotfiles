---
name: rearchitect
description: The rewrite ritual for an app that has become hard to change - pin behavior with black-box tests and goldens first, then move code without changing tests. Use when the user says the app is hard to modify, agents struggle with simple requests, regressions keep appearing, or asks to rearchitect or make the architecture production grade.
---

# Rearchitect

The evidence behind this ritual: https://claude.ai/code/artifact/a91546e8-9859-44e1-a622-851f73a554ae (part IV).

Timing check first. The trigger is "agents struggle with simple requests" or "every change regresses something", and the precondition is that the domain is now understood. If the product is still being discovered, say so and don't start; a rewrite of an unknown domain rebuilds the same confusion in nicer folders.

The order is the method. Steps 1 and 2 change zero behavior, each step is at least one commit, and the app keeps working throughout.

## 1. Make everything callable from tests

Binaries become libraries with thin main shims. Every global a test needs — ports, socket paths, API base URLs, whether subprocesses spawn — becomes injectable. Its own commit, before anything moves.

## 2. Pin the contracts before moving code

- Black-box tests that speak only the public protocol (socket, HTTP, CLI output, rendered frame). Tests that reach internals die with the internals; these survive the rewrite.
- Goldens of whole outputs (journals, snapshots), rewritable only by a bless command that prints the diff. The named assertion documents the rule; the golden catches the effect nobody meant to add.
- Prove each new suite by deliberately breaking the code and watching exactly the right test fail, and nothing else.
- Tests own all their resources (ports, directories, databases, locks). Anything shared with the developer's live environment produces failures that are never the code's fault.

## 3. Move the code

A refactor that changes a test is not a refactor. When collapsing duplicated copies, every divergence between them is settled as an explicit recorded decision — which side wins and why, in the commit message — never a silent merge. For a UI rewrite, build the new front end as a parallel implementation beside the old one, on the same core and protocol; the old one stays working and untouched until replaced.

## 4. Hold existing debt with a limit that only tightens

Grandfather current offenders at their current size in a checked-in list; the gate fails if any grows, and the list only shrinks. Pay it down to empty, then it is a plain wall. A hard wall on day one gets turned off; a warning scrolls past. Delete the crude gate the day real tooling replaces it.

## 5. Hunt orphans

After the move, sweep for: config knobs nothing reads, writers whose reader was deleted, files that fell out of the build, hand-maintained duplicate mappings. Each one found in the source history had already rotted into a bug by the time someone looked. Forced file splits are a search tool too — reading code to move it is when dead copies and misfiled pieces surface.

## 6. Land the first feature through the new shape the same day

One real feature, through every layer, both front ends if there are two. That commit is the architecture's acceptance test; if it isn't small, the rewrite missed its target.

## 7. Encode what was learned

Every rule born from an incident during the rewrite goes into AGENTS.md the same day, named after the bug it prevents. Anything broken twice becomes a check behind the one ci command — a dumb substring scan with an error message that states the rule is enough.

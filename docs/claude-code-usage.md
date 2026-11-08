# Claude Code: why usage drains, and what to do

Based on one real case (Nov 4–5, 2026): a 111 MB session on Opus lost 10–15% of the limit at a time.

## How the prompt cache works

- Every turn sends the whole conversation. The cache lets Anthropic reuse the already-processed prefix.
- **Cache read** is cheap. **Cache write** (a rewrite) is expensive.
- The cache expires after a TTL (5 minutes by default, 1 hour on the longer tier; our transcripts show the 1-hour tier).
- After the cache expires, the next message rewrites the full context. Cost scales with context size, not with message size.
- Each subagent or fork has its own cache. Starting one on a big context pays a fresh write.

## What we saw

- Context of 440–860K tokens. Eight cold rewrites in two days (440–860K tokens each, about 4.7M in total).
- The loop: rate limit hit, stall longer than the TTL, cache expires, resume pays a full rewrite, limit hit again.
- Subagents wrote about as many tokens as the main session (3.3M vs 3.5M on Nov 5).
- Even with a warm cache, a 650K context re-reads 650K tokens on every turn.
- Agent progress summaries were also burning tokens. This is fixed upstream, so update Claude Code and drop the `CLAUDE_CODE_DISABLE_AGENT_PROGRESS_SUMMARIES` workaround once you have the fix.
- Not proven: whether context-mode helps. Treat it as an experiment.
- Not known: how Anthropic weights cache reads against limits.

## What to do

1. Keep sessions small. Start a new session per task instead of resuming a huge one.
2. After a rate limit, don't resume a big session. Run `/compact` first, or start fresh. One compaction costs one rewrite and shrinks every later one.
3. Run `/compact` before stepping away for more than the TTL.
4. Don't spawn subagents, forks or `/loop` from a big context.
5. Use Sonnet for routine work. Keep Opus for hard problems.

## How to check your own sessions

Transcripts are in `~/.claude/projects/<project>/<session>.jsonl`. Each assistant message has `usage.cache_creation_input_tokens` and `usage.cache_read_input_tokens`.

- A large creation value after a gap longer than the TTL is a cold rewrite.
- Count distinct message ids. One message is logged once per content block.
- Subagent transcripts are in the session's `subagents/` folder. Include them.

## Links

- Prompt caching docs: https://code.claude.com/docs/en/prompt-caching
- Pricing: https://platform.claude.com/docs/en/about-claude/pricing
- Open request about the burn: https://github.com/anthropics/claude-code/issues/86879
- Related issues: https://github.com/anthropics/claude-code/issues/105981 and https://github.com/anthropics/claude-code/issues/104358
- Cache-tax plugin: https://github.com/karanb192/cache-tax

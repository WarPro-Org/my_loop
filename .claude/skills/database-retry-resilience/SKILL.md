---
name: database-retry-resilience
description: Use when enabling/handling EF Core EnableRetryOnFailure (Neon scale-to-zero cold starts) or writing/reviewing any explicit BeginTransaction. A retrying execution strategy throws on bare transactions and re-runs blocks, so transactions must be execution-strategy-wrapped and idempotent.
origin: extracted-from-session-2026-06-28
tools: Read, Write, Edit, Bash, Grep, Glob
---

# Database Retry Resilience

## When to Activate

- Turning on (or already running with) Npgsql `EnableRetryOnFailure` — required for Neon's
  scale-to-zero cold starts.
- Writing or reviewing **any** code with an explicit `BeginTransaction(Async)`.
- Editing a connection string for Neon.

## The trap

`EnableRetryOnFailure` installs `NpgsqlRetryingExecutionStrategy`, which **throws
`InvalidOperationException: does not support user-initiated transactions` *eagerly*** — on the
first `BeginTransactionAsync` outside an execution strategy, with or without an actual failure.
MyLoop's three explicit transactions (`TerritoryService.ProcessClaim`, `ProcessBatchStepClaim` —
both `Serializable` — and `LeaderboardService.RefreshLeaderboard`) are on hot paths; flipping on
retry without fixing them crashes the core capture path on the first claim.

## The rule

1. **Wrap every explicit transaction** in `db.Database.CreateExecutionStrategy().ExecuteAsync(async () => { … })`.
   With retry off (e.g. tests building their own `UseNpgsql` context), this is a harmless passthrough.
2. **Make the wrapped block idempotent** — the strategy re-runs the *whole* block on a transient
   error, reusing the **same DbContext** (ChangeTracker is NOT auto-reset):
   - Call `_db.ChangeTracker.Clear()` at the top of the block / each retry iteration.
   - Watch for **additive** mutations on persistent state (`user.Counter++`) — they compound across
     retries unless the clear forces a fresh re-read (this bit `RefreshLeaderboard.UpdateAchievementCounters`).
   - Delete-then-reinsert / upsert patterns are naturally idempotent.
3. **Don't let a rollback mask the trigger.** In a bare `catch`, a rollback on a dead connection can
   throw and replace the original transient exception, so the strategy can't classify it as retriable.
   Guard the rollback (log + swallow) and `throw;` the original.
4. **Layer, don't fight:** an inner manual retry loop for serialization conflicts (40001/40P01/23505)
   and the outer EF strategy for connection-level transients are disjoint — keep both.
5. **Post-commit side effects** (SignalR/FCM/push) happen AFTER `CommitAsync`, never inside the
   retriable block, or a retry double-fires them.

## Connection-string gotchas (Npgsql 10 + Neon)

- Use `Timeout=<sec>`; `Connection Timeout=` throws `ArgumentException: Couldn't set connection timeout`.
- Npgsql does **not** parse `postgresql://` URIs — convert to key-value
  (`Host=…;Database=…;Username=…;Password=…;SSL Mode=Require;Timeout=30`).
- Keep the real string in **user-secrets**, never in `appsettings.json` (localhost placeholder only).

## Checklist
- [ ] Every `BeginTransaction` is inside a `CreateExecutionStrategy().ExecuteAsync`
- [ ] The block resets state (`ChangeTracker.Clear()`); no additive-on-persistent-state writes survive a retry
- [ ] Post-commit side effects are outside the retriable block
- [ ] Rollback in `catch` is guarded so it can't mask the original exception

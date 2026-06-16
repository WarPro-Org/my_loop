---
name: coding-standards
description: Cross-language code-quality bar for MyLoop (C# and Dart) — function size/single-responsibility, no magic numbers or strings, intention-revealing naming, comments that explain WHY, structured logging without secrets/PII, and disciplined exception handling. Use when writing or reviewing any production code. Defers language idioms to dotnet-patterns / dart-flutter-patterns.
origin: MyLoop (staff-engineering standard)
---

# Coding Standards — Cross-Language Quality Bar

A language-agnostic baseline so a junior and a senior read the same code the same way.
This skill owns *quality habits*; **language idioms are out of scope** — defer to
`dotnet-patterns` (C#) and `dart-flutter-patterns` / `flutter-dart-code-review` (Dart).

## When to Activate

- Writing or reviewing any production C# or Dart
- Any PR not purely docs/config

## Rule 1 — Functions do one thing; ~50 lines is a review trigger, not a hard cap

A function over **~50 lines** must justify itself: if it has more than one reason to
change, split it. Do **not** extract single-use helpers purely to win a line count — a
cohesive 60-line function beats five fragmented 12-line ones. The real test is single
responsibility and nesting depth (aim for ≤3 levels; use guard clauses to flatten).

> Reviewer prompt: "What is this function's one job?" If the answer needs an "and", split.

## Rule 2 — No magic numbers or strings

Every literal with meaning gets a name. Tunables and domain values live in a constants
home, not inline.

- **C#:** `Constants/` (`GameConstants`, `AntiCheatConstants`, `ApiRoutes`, `FirebaseClaims`, `InfrastructureDefaults`)
- **Dart:** a `*_constants.dart` / `const` in the feature, never a bare literal in a widget/provider

```csharp
// Bad
if (loop.Hexes.Count > 1200) ...
// Good
if (loop.Hexes.Count > GameConstants.MaxHexesPerLoop) ...
```

Exempt: `0`, `1`, `-1`, empty string, and `true/false` used in their obvious arithmetic/
sentinel sense.

## Rule 3 — Intention-revealing names; follow each language's casing

Names say what a thing *is/does*, not its type or how it's implemented.

| | C# | Dart |
|---|---|---|
| Types | `PascalCase` | `PascalCase` |
| Methods/functions | `PascalCase` | `camelCase` |
| Locals/params | `camelCase` | `camelCase` |
| Private fields | `_camelCase` | `_camelCase` |
| Constants | `PascalCase` | `lowerCamelCase` (`const`) |
| Async methods | suffix `Async` | (no suffix; return `Future`) |

No abbreviations beyond well-known ones (`id`, `url`, `db`). Booleans read as predicates
(`isClaimed`, `hasPendingWrites`). No `data`, `temp`, `obj`, `mgr`, `helper` as names.

## Rule 4 — Comments explain WHY, never WHAT

Code says what; comments justify the non-obvious: an invariant, a workaround, a spec
reference, a race-condition guard. Delete comments that restate the code. **No
commented-out code on master.** Use `// TODO(owner): …` only with an owner and an issue —
and per project rule, no stub-with-TODO without explicit sign-off.

```csharp
// Bad:  // increment the counter
counter++;
// Good: server is authoritative — client count is advisory only (over-count bug, PR #28)
counter = serverLoopCount;
```

## Rule 5 — Logging is structured, leveled, and leak-free

- Use structured/templated logging (Serilog message templates in C#), not string concat.
- Levels: `Error` = needs action, `Warning` = recoverable anomaly, `Information` =
  business milestone, `Debug` = dev only. No `Information` spam in hot/GPS loops.
- **Never log** JWTs, Firebase tokens, secrets, full coordinates of a user, or PII.
- Every caught error that isn't rethrown is logged with context.

```csharp
_logger.LogInformation("Loop {LoopId} claimed by {UserId} ({HexCount} hexes)",
    loop.Id, userId, loop.Hexes.Count); // structured, no token, no raw GPS
```

## Rule 6 — Exception handling is deliberate

- **Never swallow.** No empty `catch {}`. Catch only what you can handle.
- Catch the **narrowest** type; let unexpected exceptions bubble to the central
  middleware/error boundary.
- Rethrow with context (`throw;` to preserve stack, or wrap in a domain exception) — see
  the `error-handling` skill for the offline/durability cases.
- Validate inputs with guard clauses up front; don't use exceptions for normal control flow
  (prefer the Result pattern for expected failures — see `dotnet-patterns`).

## Pre-PR Checklist

- [ ] No function smuggling multiple responsibilities; >50-line functions justified
- [ ] Zero magic numbers/strings — meaningful literals are named constants
- [ ] Names reveal intent and follow the casing table; async/`Async` convention honored
- [ ] Comments explain *why*; no commented-out code; TODOs owned
- [ ] Logging structured, correctly leveled, no secrets/tokens/PII/raw GPS
- [ ] No empty catches; narrow catch types; unexpected errors reach the central boundary

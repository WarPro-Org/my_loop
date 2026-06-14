## What & why

<!-- Explain the "why", not just the "what". -->

## Pre-PR Skill Gate

Run the skill(s) relevant to what this PR touches (see CLAUDE.md → Pre-PR Skill Gate),
then check the boxes that apply and note which skills you ran.

- [ ] .NET API code → `dotnet-patterns`, `csharp-testing`
- [ ] DB schema / EF migrations / hex counts → `database-migrations` (atomicity + explicit transactions)
- [ ] API endpoints / request-response shapes → `api-design`
- [ ] **Cross-stack (.NET ↔ Flutter)** → field names, types (H3 CellId, UserId), constants verified to match on both sides
- [ ] Auth / anti-cheat / client coords / rate limits / secrets → `security-review`
- [ ] SignalR / real-time / caches / offline queues → `latency-critical-systems`
- [ ] Flutter / Dart / Riverpod state → `dart-flutter-patterns`, `flutter-dart-code-review`
- [ ] Error handling / offline durability → `error-handling`
- [ ] **Final gate** → `verification-loop` (tests green) + PR review

**Skills run:** <!-- list them -->

## Testing

<!-- How was this verified? -->

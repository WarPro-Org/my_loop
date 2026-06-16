---
name: flutter-disk-concurrency-test
description: Pattern for regression-testing a Flutter service that persists to disk and/or serializes async ops (WAL, cache). Stub path_provider via the platform interface, assert the disk-vs-memory durability invariant, and prove the test fails without the fix.
origin: extracted-from-session-2026-06-15
---

# Prove a Flutter disk/concurrency regression test by reverting the fix

## When to Activate
Writing a regression test for a Flutter service that persists to disk (write-ahead
log, cache) and/or serializes async operations — especially when it uses `path_provider`.

## Pattern
- **Stub `path_provider` with the platform interface, not a method-channel mock.**
  Subclass `PathProviderPlatform with MockPlatformInterfaceMixin`, override
  `getApplicationDocumentsPath` to return a `Directory.systemTemp.createTemp(...)`
  path, assign it to `PathProviderPlatform.instance` in `setUp`, delete the temp dir
  in `tearDown`. Add `path_provider_platform_interface` + `plugin_platform_interface`
  to `dev_dependencies` so the imports don't trip `depend_on_referenced_packages`.
- **Test the durability invariant, not just memory.** After an awaited batch of ops,
  reopen a fresh instance that reads only from disk and assert it equals the live
  in-memory view — AND assert the exact expected surviving set (disk==memory alone can
  pass on a regression that drops everything, leaving both empty).
- **Force the race deterministically.** Fire conflicting ops without awaiting between
  them (`Future.wait([rewrite, append, append])`) and loop ~25 iterations.
- **Prove the test catches the bug.** Temporarily restore the pre-fix source
  (`git show <fix>^:path > file`), run the test, confirm it FAILS, then restore the
  fixed version. A regression test that never fails without the fix guards nothing.

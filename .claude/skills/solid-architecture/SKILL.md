---
name: solid-architecture
description: SOLID and MyLoop's module rules for any C# or Dart change — one job per class, extend without rewriting, honest subtypes, small interfaces, depend on abstractions; modules reached only through their public interface, internals internal, no shared tables, thin controllers, features behind abstractions; where constants, settings and interfaces belong. Use when writing or reviewing production C# or Dart. Code quality habits are coding-standards'; language idioms are dotnet-patterns' and dart-flutter-patterns'.
origin: MyLoop (CLAUDE.md "Architecture Rules")
---

# SOLID and module rules

CLAUDE.md says "Always follow SOLID" and "independent modules in one app". This skill turns that into checks
a reviewer can answer with yes or no for every class, file and dependency the change adds or edits. Each
"no" is a finding: say what is wrong, how it hurts (what change becomes hard or risky) and what to change.

## When to activate

- Any change to production C# (`api/`) or Dart (`mobile/lib/`).
- Reviewing such a change: the independent reviewer runs this checklist too.

## 1. Single responsibility — one reason to change

- [ ] Each new or changed class has one job you can say without "and" (e.g. "checks the rules at startup").
- [ ] Values that belong to that job live in that class, as private named constants. Moving them to a shared
      constants class would spread one job over two files. A value that **several** classes need goes in one
      home: game-rule numbers in `GameRules` (appsettings.json, via `IRuleSettings`), other shared values in
      the owning module, or `Constants/` for old beta code in `MyLoop.Api`.
- [ ] A value that must be tuned without a code change is a setting (`GameRules`), not a constant. A value that
      guards the settings themselves (e.g. the validator's upper limits) stays in code, so a typo in the file
      can't loosen it.
- [ ] Controllers, hubs and widgets hold no business logic: they call one module or provider and map the result.

## 2. Open/closed — extend without rewriting

- [ ] A later FR can add behaviour by adding a class or registration, not by editing a growing `switch` or `if`
      chain in shared code. Reflection or registration lists are fine (e.g. `GameRulesPresenceValidator` covers
      a new setting with no change).
- [ ] No "for later" settings, flags or parameters (CLAUDE.md "Stay on the goal"): extension points are added
      when an FR needs them.

## 3. Liskov — subtypes keep the promise

- [ ] A class implementing an interface (or a fake in a test) honours the whole contract: same nullability, no
      new exceptions the caller doesn't expect, no "not supported" methods.
- [ ] Test fakes of a module behave like the real one for what the test uses; a fake that skips a rule the real
      code enforces hides bugs.

## 4. Interface segregation — small interfaces

- [ ] A module's public interface holds only what other modules call. Server-only data stays out of what the
      app sees (e.g. `ClientRules` vs `GameRules`).
- [ ] No caller depends on methods it never uses; split the interface instead of adding to it.

## 5. Dependency inversion — depend on abstractions

- [ ] Classes get their dependencies through the constructor (DI), never `new` a service, call a static
      singleton, or look things up through `IServiceProvider` (service locator).
- [ ] Dart features depend on abstractions (e.g. `ILocationSource`), not on a concrete plugin; providers are
      overridable in tests.
- [ ] An interface exists only where there is a second implementation or a real test seam — not one per class.

## 6. MyLoop module rules

- [ ] New 0.1 server logic lives in a module (`api/MyLoop.Modules.<Name>/`), not in `MyLoop.Api/Services/`.
- [ ] Other code uses only the module's public interface. Implementation classes are `internal`; the module's
      boundary test (e.g. `tests/MyLoop.V01.Tests/FR1/RulesModuleBoundaryTests.cs`) lists every public type,
      and a new public type is a deliberate change to that list.
- [ ] A module never reads another module's database tables or internal classes.
- [ ] A module registers itself with one `AddMyLoop<Name>` extension; `Program.cs` only calls it
      (`webapi-standards`).
- [ ] Nothing in a module references `MyLoop.Api` (the dependency points from the host to the module).

## How to run it

1. List the changed production files (`git diff --name-only origin/master...HEAD -- api mobile/lib`).
2. For each new or changed class, file and dependency, answer every box above that applies.
3. Record the result in the PR's "Skills run" with any findings and their fix commits. A box answered "no"
   without a fix is either fixed before the PR or written as an accepted exception with its reason.

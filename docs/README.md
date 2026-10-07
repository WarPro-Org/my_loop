# MyLoop Documentation

This is the canonical, in-repository knowledge base for MyLoop. **No external tools
(Notion, Confluence, etc.) are used** — every decision, plan, runbook, and learning
lives here and versions alongside the code it describes.

## Layout

| Folder | What lives here |
|--------|-----------------|
| `architecture/` | How the system actually works — system overview, claim pipeline, spatial model, real-time contract, and the full [frontend↔backend reference](architecture/frontend-backend-reference.md) (every endpoint, SignalR hub, and provider mapping). |
| `product/` | Product & technical [spec](product/spec.md) and the game-design [decision log](product/design-log.md) — what we're building and why. |
| `versions/` | Per-version functional requirements, agreed before design or code — start at the [versions index](versions/README.md). Each version folder holds `requirements.md` and `design/` (FR design docs), `records/` (one page per finished FR), `audits/` (audit reports) and `bugs/` (bug reports). |
| `scenarios.md` | The catalogue of every edge case; every FR design doc answers each ID. |
| `data-removals.md` | Every file that deletes, overwrites, hands over or expires user data, with its verdict. |
| `design/` | Design reviews from the multiplayer beta (before 0.1). |
| `decisions/` | Architectural Decision Records (ADRs). One file per decision, **append-only** once Accepted. |
| `runbooks/` | Operational procedures — deploys, DB migrations, incident response. |
| `compliance/` | Apple App Store review, privacy manifest mapping, data-deletion guarantees. |
| `learnings/` | The story behind rules: what surprised us and why a rule exists. Not needed to follow the rules. |

Which of these to read before planning, design, coding, reviewing or fixing a bug is set by the **Docs map** in
the root `CLAUDE.md`; "PR rules" fails a PR that adds a folder or top-level file the map doesn't name.

## How to contribute docs

1. **Made an architectural choice?** Write an ADR (`decisions/`). Copy `decisions/0000-template.md`,
   bump the number, fill it in, set status to `Proposed`, then `Accepted` once agreed.
   **Never edit an Accepted ADR** — supersede it with a new one that links back.
2. **Changed how the system works?** Update the relevant file in `architecture/` in the
   *same PR* as the code change. Docs that drift are worse than no docs.
3. **Discovered something non-obvious?** Turn it into something Claude reads anyway — a rule in `CLAUDE.md`, a
   skill, a `scenarios.md` ID or a "PR rules" check — in the same PR, then add the story as a dated entry to
   `learnings/<phase>.md`.
4. **Wrote/changed an operational step?** Update the relevant `runbooks/` file.

## Source of truth

Where this documentation and the root `README.md` disagree, **this folder wins** and the
root README should be corrected in the same PR.

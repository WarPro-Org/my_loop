---
name: myloop-closing-an-fr
description: MyLoop's steps for closing an FR (final audit, blind audit, triage and freeze, the FR record, spec and design doc status, close-out PR, task and parent task, branches) and for keeping an earlier FR's record true when a later FR changes it. Use when an FR's last PR merges, or when a change touches something an FR record states.
origin: MyLoop (moved from CLAUDE.md to keep it small)
---

# Closing an FR

Moved word for word from CLAUDE.md.

**Closing an FR** — after its last PR merges, before telling the user it's done. The goal: someone (human or AI)
working on the app years later, e.g. in version 100.2, can find this FR and understand its scope, what it built and
what must stay true, in a few minutes.
1. **Final audit on master:** an independent agent checks every spec line, acceptance criterion, design-doc matrix
   cell, user situation and linked item (task, parent task, every PR, spec, design doc), re-running a "red when" per
   test group. Findings are fixed in a new PR of the FR (or accepted by the owner) before the FR is closed.
   It also runs a **blind audit**: 4–6 agents that are given only the version's `requirements.md` and the code, never
   the task, design doc, PRs or record, each searching one area for every way it can go wrong. Every finding
   becomes a `docs/scenarios.md` ID, or a row under an existing one. Save the report in
   `docs/versions/<release>/<version>/audits/`.
   **Triage once, then freeze.** Each finding is sorted once: it stays with this FR only if it is in code this FR
   wrote and breaks this FR's own spec. Anything else goes to the later FR that builds or rebuilds that code (a
   bullet in its spec section and an `open FRn` design-doc row) or to a bug task. After this triage the FR's list
   is frozen: nothing found later is added to it — it goes to the owning FR or a bug task.
2. **FR record:** `docs/versions/<release>/<version>/records/frN-<name>.md`, one page, for humans and AI agents:
   - **Status** line with the task, spec, design doc and every PR;
   - **Scope:** in and out;
   - **What shapes the app:** a table of area → what exists → where (modules, endpoints, data and contracts,
     settings, app state, key files);
   - **Decisions that must stay true**, each with its reason;
   - **Left to later FRs**, each naming the FR;
   - **Known limits**;
   - **How to change it** (e.g. tune a setting);
   - **Tests that guard it**.

   Facts only, no history. The design doc keeps the full matrix, risks and history, and points to the record.
3. **Spec and design doc:** the FR's section in `requirements.md` gets `**Status:** done (task #N)` and the record's
   path; the design doc's first lines point to the record.
   Steps 2–3 go in one docs-only **close-out PR**: title `<version> > FRN > Close-out record`, a branch that is not
   `vX.Y/frN-…` (it is not a numbered part, so the FR's PRs are not renumbered), a `Task: #N` line, and the usual
   gates, independent review and owner merge. The record's Status line lists it. Steps 4–7 happen after it merges.
4. **Task:** a Summary at the top (3–6 lines and the record's path), every criterion ticked with the PR that met it,
   the Progress table with each merge commit, the check-in log complete; then close it.
5. **Parent version task:** the FR row says done, with the record's path.
6. **Branches:** delete the FR's merged branches, the close-out branch included. If the session can't delete them,
   list them for the owner.
7. **Report** to the user only after steps 1–6 hold.

**Keeping records true later:** an FR record is a linked item for as long as the app exists. A later FR that
changes something an earlier record states (a value, a behaviour, a limit, a deferred item it now builds) updates
that record in the same PR, and its own record names the change.

# Decisions

This document records decisions made during the development of `todo`.

The purpose is to avoid repeatedly debating the same things, forgetting why something was done, or accidentally contradicting an earlier design decision.

Only decisions that have actually been made belong here.

Unresolved ideas belong in `IDEAS.md`.

---

## Project

### D001 — Project name

**Decision:** The project is named `todo`.

**Reason:** Naming things is hard. Also, the name is thematically appropriate given the project's uncertain completion date.

### D002 — Implementation language

**Decision:** The language implementation will be written in Odin.

**Reason:** Odin provides the low-level control and programming experience desired for this project.

### D003 — Initial implementation strategy

**Decision:** Begin with a tree-walk interpreter.

**Reason:** An interpreter allows language features to become usable incrementally without requiring a compiler or native code generation.

### D004 — Language implementation reference

**Decision:** Use *Crafting Interpreters* by Robert Nystrom as an implementation reference.

**Reason:** Its incremental approach provides a proven starting point while leaving room for our own language design decisions.

### D005 — Source file extension

**Decision:** Language source files will use the `.todo` extension.

**Reason:** Obviously.

---

## Development philosophy

### D006 — Incremental development

**Decision:** Implement features incrementally and prioritize working functionality over speculative architecture.

**Reason:** There is no point designing a sophisticated solution to a problem we haven't encountered yet.

### D007 — Deferred decisions

**Decision:** Unresolved design questions will be recorded separately rather than prematurely decided.

**Reason:** Not every question needs an answer today. Some questions don't even need an answer this year.

---

### D008 — Runtime memory management

**Decision:** Start with interpreter-lifetime allocation for runtime objects, intentionally deferring individual reclamation. (Yep, it's gonna get chonky) Implement a tracing garbage collector later, following the approach in Crafting Interpreters.

**Reason:** Implementing a garbage collector on day one is a mistake because we don't know what the language needs yet.

## Future decisions

Add new decisions as they are made.

Use the following format:

### DXXX — Decision title

**Decision:** What was decided?

**Reason:** Why was it decided?

**Consequences:** What does this decision affect? (Optional)

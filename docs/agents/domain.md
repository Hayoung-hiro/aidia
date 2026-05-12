# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Layout

AIDIA uses a **single-context** layout (one R package, one domain):

```
/
├── CLAUDE.md                       ← project rules and architecture
├── docs/
│   ├── domain-knowledge.md         ← domain glossary (DPPP, strategies, instruments, etc.)
│   ├── astral-instrument-knowledge.md
│   └── adr/                        ← architectural decision records
└── R/
```

This repo does **not** use a root-level `CONTEXT.md`. The domain glossary lives at `docs/domain-knowledge.md` — read it first when you need to learn the project's vocabulary (DPPP, FWHM, cycle time, sync-optimal, forbidden zone, strategies, etc.).

## Before exploring, read these

- **`docs/domain-knowledge.md`** — the domain glossary. Treat it as the `CONTEXT.md` for this repo.
- **`docs/astral-instrument-knowledge.md`** — instrument-specific deep-dive (Astral architecture, AGC, IT tradeoffs).
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If `docs/adr/` is empty or a file doesn't exist, **proceed silently**. Don't flag the absence; don't suggest creating files upfront. The producer skill (`/grill-with-docs`) creates them lazily when terms or decisions actually get resolved.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `docs/domain-knowledge.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/grill-with-docs`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-NNNN (title) — but worth reopening because…_

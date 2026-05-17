# Code review prompt (Fitloop)

Use when reviewing a branch diff against `main`.

## Scope

- Rails: `app/`, `config/`, `spec/`
- Nesting engine: `nesting_engine/`
- Core docs: `docs/core/` when behavior or boundaries change

## Quality commands

```bash
.venv/bin/pytest nesting_engine/ -q
bin/rubocop -f github
bin/rails test
```

## Review criteria

1. **Architecture** — Nesting math stays in Python; Rails orchestrates CLI only (`docs/core/SYSTEM_ARCHITECTURE.md`).
2. **Margin vs kerf** — `margin_mm` is sheet-edge inset only; `kerf_mm` is piece-to-piece via `nest_types.apply_kerf` (`REQ-FIT-NEST-002`).
3. **Traceability** — New nesting tests tag `[REQ-FIT-*]` from `docs/core/SPEC.md`.
4. **Deterministic coding** — Functions ≤ 60 lines; cyclomatic complexity ≤ 10 (`docs/core/deterministic_coding_standards.md`).
5. **Contracts** — Prefer invariant assertions over golden x/y coordinates for placement output.

## Output format

Categorize findings as **MUST FIX**, **STRONGLY RECOMMENDED**, or **NICE TO IMPROVE** with hierarchical numbering.

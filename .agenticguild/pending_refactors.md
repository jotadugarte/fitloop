# Pending Refactors & Tech Debt
*The AI will append items to this list when it discovers architectural violations outside the scope of its current task.*

| Date | File/Module | Issue Description | Proposed Fix |
|---|---|---|---|
| 2026-05-17 | `nesting_engine/` | Domain distances use raw `float` (`margin_mm`, `kerf_mm`, sheet dims) instead of branded types (`Millimeters`, `Degrees`) approved in task session | Introduce typed aliases or small value objects; thread through `nest_bin` / `nest_spike` / CLI config without changing Rails API |

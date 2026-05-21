# PR split guidance (large feature branches)

When a branch bundles multiple shipped features (e.g. progress UX + auto-split + composite layers + `es_panic`), prefer stacked PRs for review and CI:

1. **Nesting progress** — CLI `progress.json`, `ProgressSnapshot`, Turbo panel (`REQ-FIT-JOB-001`)
2. **Auto-split** — models, `split_planner.py`, orphan UI (`REQ-FIT-SPLIT-001`)
3. **Composite DXF** — `layer_role`, `composite_extract` (`REQ-FIT-DXF-002`)
4. **Locales** — `:es_panic` and switcher (`REQ-FIT-UI-005`)

If the branch is already pushed as one unit, use a single PR with a sectioned description matching the commits above.

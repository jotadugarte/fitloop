# Fitloop — manual QA checklist (MVP v1)

**Requirement:** [REQ-FIT-QA-001](core/SPEC.md)  
Use after automated specs are green. Record date, tester, and environment.

## Environment

- [ ] PostgreSQL running; `bin/rails db:migrate` applied
- [ ] `.venv` active; `pip install -r nesting_engine/requirements.txt` done
- [ ] `bin/dev` or `bin/rails server` + Solid Queue worker running

## Workspace & access

- [ ] `GET /` shows Fitloop home and logo
- [ ] `GET /projects` redirects to workspace start (`/empezar`) — no saved-project list
- [ ] `GET /empezar` creates an ephemeral workspace and shows setup (no PIN field)
- [ ] Complete setup (title, sheet stock, DXF, layers) → project show page loads
- [ ] Opening another project URL without session bind redirects to start with expired message
- [ ] Returning home discards the workspace project (session cleared)

## DXF inputs

- [ ] Upload one or more DXFs; layer checklist shows union of layer names
- [ ] Pre-flight blocks nest when no layers selected (i18n error)
- [ ] Pre-flight blocks nest when zero extractable pieces on selected layers

## Nesting job

- [ ] Start nesting → progress updates; completes with `completed` or `partial` as expected
- [ ] Golden sample (`spec/fixtures/golden/sample_piece.dxf`, layer `PIECES`, sheet ≥ 200×100 mm) → **completed**, download link present
- [ ] Oversized piece on tiny sheet → **partial**, orphan listed in report, download still offered
- [ ] Cancel during processing stops job (when applicable)
- [ ] Re-nest creates new run; history lists prior runs; download reflects latest result

## Outputs

- [ ] Download nested DXF opens in CAD viewer; sheets offset on +X
- [ ] SVG preview sheet count matches `placements.json`
- [ ] Locales `en` / `es` show translated UI strings (spot-check)

## Security & ops

- [ ] No PIN or admin-unlock UI in the app
- [ ] No nesting math errors surfaced as 500 without flash/message

## Sign-off

| Field | Value |
|-------|--------|
| Date | |
| Tester | |
| Commit / branch | |
| Notes | |

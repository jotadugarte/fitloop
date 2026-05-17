# Fitloop — manual QA checklist (MVP v1)

**Requirement:** [REQ-FIT-QA-001](core/SPEC.md)  
Use after automated specs are green. Record date, tester, and environment.

## Environment

- [ ] PostgreSQL running; `bin/rails db:migrate` applied
- [ ] `.venv` active; `pip install -r nesting_engine/requirements.txt` done
- [ ] `bin/dev` or `bin/rails server` + Solid Queue worker running

## Project & access

- [ ] `GET /` shows Fitloop home and logo
- [ ] `GET /projects` lists projects without login
- [ ] Create project with title, 6-digit PIN, at least one sheet stock (finite and ∞ cases)
- [ ] Open project → PIN gate appears; wrong PIN rejected; correct PIN unlocks show page

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

- [ ] Admin master PIN (credentials) unlocks any project; rate limit behaves
- [ ] No nesting math errors surfaced as 500 without flash/message

## Sign-off

| Field | Value |
|-------|--------|
| Date | |
| Tester | |
| Commit / branch | |
| Notes | |

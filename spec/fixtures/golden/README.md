# Golden DXF fixture (REQ-FIT-QA-001)

`sample_piece.dxf` is the canonical end-to-end fixture for Fitloop system specs.

- **Layer:** `PIECES` (closed rectangle 200×100 mm)
- **Regenerate:** `python scripts/generate_sample_dxf.py` (requires ezdxf in the Python venv)
- **Source of truth:** Keep in sync with `nesting_engine/tests/fixtures/sample_piece.dxf`

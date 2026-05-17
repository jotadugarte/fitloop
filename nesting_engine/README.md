# nesting_engine

Python package for Fitloop DXF extraction and sheet nesting. Rails invokes the engine via **CLI** (v1); see `docs/core/SPEC.md` § CLI Contract.

## Working directory layout

Rails `Nesting::CliRunner` creates a per-run directory containing:

| Path | Writer | Description |
|------|--------|-------------|
| `config.json` | Rails | Job parameters and absolute paths |
| `inputs/*.dxf` | Rails | Copies of uploaded input DXFs |
| `output/` | Python CLI | `nested.dxf`, `placements.json`, `report.json` |

## `config.json` schema

```json
{
  "project_id": "42",
  "input_dxf_paths": ["/abs/path/to/inputs/piece_a.dxf"],
  "included_layers": ["PIECES"],
  "sheet_stocks": [
    {
      "width_mm": 1220.0,
      "height_mm": 2440.0,
      "quantity": 5,
      "sort_order": 0
    },
    {
      "width_mm": 1000.0,
      "height_mm": 2000.0,
      "quantity": null,
      "sort_order": 1
    }
  ],
  "kerf_mm": 0.0,
  "margin_mm": 5.0,
  "curve_tolerance_mm": 0.1,
  "sheet_gap_mm": 15.0,
  "time_limit_sec": 600,
  "output_dir": "/abs/path/to/output"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `project_id` | string | yes | Correlation id (Rails `Project#id`) |
| `input_dxf_paths` | string[] | yes | Absolute paths to input DXF files |
| `included_layers` | string[] | yes | Layer names from project layer filter |
| `sheet_stocks` | object[] | yes | Ordered sheet inventory |
| `sheet_stocks[].width_mm` | number | yes | Sheet width (mm) |
| `sheet_stocks[].height_mm` | number | yes | Sheet height (mm) |
| `sheet_stocks[].quantity` | number \| null | yes | `null` = unlimited sheets |
| `sheet_stocks[].sort_order` | integer | yes | Consumption priority (ascending) |
| `kerf_mm` | number | yes | Tool kerf (mm) |
| `margin_mm` | number | yes | Sheet margin (mm) |
| `curve_tolerance_mm` | number | yes | Curve flattening tolerance (mm) |
| `sheet_gap_mm` | number | yes | Horizontal gap between sheets in output DXF (mm) |
| `time_limit_sec` | integer | yes | Safety time cap for nesting |
| `output_dir` | string | yes | Directory for engine output files |

## Output files (`output_dir`)

| File | Description |
|------|-------------|
| `nested.dxf` | Combined nested DXF; sheets offset +X by `sheet_gap_mm` |
| `placements.json` | Piece placements per sheet (preview) |
| `report.json` | Status hint, orphans, warnings |

### `report.json` (minimum)

```json
{
  "status": "completed",
  "orphans": [],
  "warnings": []
}
```

| `status` | Meaning |
|----------|---------|
| `completed` | All extractable pieces placed within time limit |
| `partial` | Time cap or orphans; best-so-far nested DXF |
| `failed` | Unrecoverable error |

## CLI entry points (v1)

| Script | Purpose |
|--------|---------|
| `cli_mock.py` | Test/dev mock: writes stub outputs (P3 bridge tests) |
| `read_layers.py` | Layer name discovery |
| `count_pieces.py` | Pre-flight piece count |
| `nest.py` | Full nest pipeline (multi-bin, outputs) |

Invocation:

```bash
python nesting_engine/cli_mock.py /path/to/workdir/config.json
```

Exit code `0` when outputs are written; non-zero on failure.

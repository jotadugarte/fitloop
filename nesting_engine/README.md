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
  | `time_limit_sec` | integer | yes | Safety time cap for nesting; override via env `FITLOOP_NESTING_TIME_LIMIT_SEC` on Rails |
  | `optimization_mode` | string | no | `fast` (default) or `thorough`; Rails sets via `FITLOOP_NESTING_OPTIMIZATION_MODE` |
  | `max_seeds` | integer | no | Thorough multi-start cap (default 16); env `FITLOOP_NESTING_MAX_SEEDS` |
  | `max_local_search_iterations` | integer | no | Thorough local-search cap (default 12); env `FITLOOP_NESTING_MAX_LOCAL_SEARCH_ITERATIONS` |
  | `output_dir` | string | yes | Directory for engine output files |

### Composite layers per file (`input_files`) — v1.2

When the user sets a **primary layer** per DXF file (`REQ-FIT-DXF-002`), Rails emits `input_files[]` instead of top-level `input_dxf_paths` + `included_layers`. Legacy projects without a primary layer keep the flat fields above.

```json
{
  "project_id": "42",
  "input_files": [
    {
      "path": "/abs/path/to/inputs/panel.dxf",
      "primary_layer": "CORTE",
      "auxiliary_layers": ["GRABADO", "TEXTO"]
    }
  ],
  "sheet_stocks": [{ "width_mm": 1220.0, "height_mm": 2440.0, "quantity": 1, "sort_order": 0 }],
  "kerf_mm": 2.0,
  "margin_mm": 5.0,
  "curve_tolerance_mm": 0.25,
  "sheet_gap_mm": 15.0,
  "time_limit_sec": 600,
  "output_dir": "/abs/path/to/output"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `input_files` | object[] | yes (composite) | One entry per input DXF |
| `input_files[].path` | string | yes | Absolute path to the DXF |
| `input_files[].primary_layer` | string | yes (composite) | Layer name for cut outlines |
| `input_files[].auxiliary_layers` | string[] | no | Engraving/mark layers clipped to primary polygons |
| `input_files[].included_layers` | string[] | yes (legacy per file) | Used when `primary_layer` is omitted |

**Extract:** `composite_extract.load_composite_pieces` builds `CompositePiece` (primary polygon + `decorations[]`). `piece_loader` uses this path when `primary_layer` is present.

**Nest output:** Primary rings and decorations are written to **original layer names** in `nested.dxf` (not forced `PIECES`). Nesting optimizer uses primary geometry only; kerf/margin unchanged.

**Source preview:** `dxf_preview.py` accepts the same per-file `input_files` shape (via JSON config `input_files`) to render clipped auxiliary polylines in the browser preview.

## Split plan mode (`mode`: `"plan_splits"`)

v1.1 auto-split preview (see `REQ-FIT-SPLIT-001`). Same `config.json` base fields plus:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `mode` | string | yes | Must be `"plan_splits"` |
| `piece_keys` | string[] | yes | Piece keys to plan (v1: numeric string indices into extracted pieces, e.g. `"0"`) |

**Output:** `split_preview.json` only (no `nested.dxf`, `placements.json`, or `report.json`).

```json
{
  "proposals": [
    {
      "piece_key": "0",
      "feasible": true,
      "reason": null,
      "children": [{ "label": "a", "rings": [[[0, 0], [100, 0], [100, 50], [0, 50]]] }],
      "cut_segments": [[[100.0, 0.0], [100.0, 50.0]]]
    }
  ],
  "warnings": []
}
```

When `feasible` is `false`, `reason` is `split_not_feasible` and `children` is empty.

## Output files (`output_dir`)

| File | Description |
|------|-------------|
| `nested.dxf` | Combined nested DXF; sheets offset +X by `sheet_gap_mm` |
| `placements.json` | Piece placements per sheet (preview) |
| `report.json` | Status hint, orphans, warnings |
| `progress.json` | Live nesting progress for Rails UI poll (REQ-FIT-JOB-001) |
| `split_preview.json` | Split plan preview (`plan_splits` mode only) |

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

### `progress.json` (v1)

Normative contract: **`docs/core/SPEC.md` § REQ-FIT-JOB-001**. Written atomically by `progress_reporter.py` during `nest.py` (and stepped by `cli_mock.py` in tests). Rails `Nesting::CliRunner` polls this file every ~0.2s while the subprocess runs.

```json
{
  "version": 1,
  "phase_id": "fill",
  "percent": 42,
  "pieces_total": 120,
  "pieces_placed": 48,
  "message_key": null
}
```

| Field | Type | Notes |
|-------|------|--------|
| `version` | int | Schema version (`1`) |
| `phase_id` | string | `extracting`, `fill`, `optimizing`, `consolidating`, `refining`, `writing_outputs` |
| `percent` | int | Authoritative bar fill, 0–100, monotonic within a run |
| `pieces_total` | int? | Set after extract; used for ETA heuristics in Rails |
| `pieces_placed` | int? | Updated during fill when cheap to compute |
| `message_key` | string? | Optional i18n override; else Rails maps `nesting.phase.{phase_id}` |

Updates are throttled (≥1s or ≥1% delta) to limit disk churn. Partial files are never visible (write temp + rename).

## CLI entry points (v1)

| Script | Purpose |
|--------|---------|
| `cli_mock.py` | Test/dev mock: stepped `progress.json` + stub outputs (P3 bridge tests) |
| `read_layers.py` | Layer name discovery |
| `count_pieces.py` | Pre-flight piece count |
| `nest.py` | Full nest pipeline (multi-bin, outputs) |

Invocation:

```bash
python nesting_engine/cli_mock.py /path/to/workdir/config.json
```

Exit code `0` when outputs are written; non-zero on failure.

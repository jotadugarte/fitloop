# es_panic.yml — fixes al volcar el YAML del usuario (batch 3)

Aplicar al crear `config/locales/es_panic.yml` desde el paste del chat (2026-05-19).

## Reindentar (rutas incorrectas)

| En el paste | Ruta Rails correcta |
|-------------|---------------------|
| `upload:` (raíz) | `project_layers.upload:` |
| `index:` (raíz) | `project_layers.index:` |
| `nesting.download_dxf` | `nesting.orphan_preview.download_dxf` |
| `nesting.badges.*` | `nesting.split.badge.*` |

## Renombrar clave

| Paste | Correcto |
|-------|----------|
| `projects.form.consumption_notice` | `projects.form.consumption_order_legend` |

## Interpolación

| Clave | Fix |
|-------|-----|
| `nesting.split.manual.step_1` | `%{piece_number}` (no `%{id}`) |

## Claves en es.yml sin equivalente en paste (añadir copy pánico)

```
projects.form.consumption_priority
projects.form.kerf_mm_hint
projects.form.margin_mm_hint
projects.form.edit_sheet
projects.form.delete_sheet
projects.form.sheet_actions
projects.form.quantity_unlimited
nesting.orphan_reason.no_sheet_capacity
nesting.orphan_hint.oversized_for_sheet
nesting.split.choose_pending
nesting.split.regenerate
nesting.split.accepted
nesting.split.accepted_pending_nest
nesting.split.not_feasible
nesting.split.not_feasible_accept
nesting.split.manual_mother_still_present
nesting.split.manual.no_dedup
nesting.split.manual.confirm
nesting.split.manual.resolved
nesting.split.manual.not_manual_state
nesting.split.manual.orphan_geometry_missing
nesting.split.badge.resolved
nesting.split.badge.split_applied
```

Sugerencia: reutilizar tono de entradas vecinas del paste (p. ej. `choose_pending` → "En el limbo", `not_feasible` → texto de machete imposible).

## También en en.yml / es.yml (switcher)

```
locale.labels.en
locale.labels.es
locale.labels.es_panic  # solo es_panic obligatorio; en/es para paridad del partial
```

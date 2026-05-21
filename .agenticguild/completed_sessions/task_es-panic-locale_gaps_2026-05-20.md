# es_panic — claves sin copy de broma (157 + 3 nuevas)

Generado 2026-05-19. Referencia español actual (`es.yml`).  
**Total app:** 229 claves existentes + 3 `locale.labels.*` nuevas = **232 valores** para `es_panic.yml`.

Convención: conserva `%{…}` y pluralización (`one`/`other`/`zero`) igual que en `es`.

---

## locale (nuevas + 1 existente)

| Clave | ES actual |
|-------|-----------|
| `locale.switcher_label` | Idioma |
| `locale.labels.en` | *(nuevo)* EN |
| `locale.labels.es` | *(nuevo)* ES |
| `locale.labels.es_panic` | *(nuevo)* 📐 PÁNICO |

---

## application

| Clave | ES actual |
|-------|-----------|
| `application.name` | Fitloop |
| `application.dialog_title` | Fitloop |
| `application.dialog_accept` | Aceptar |

---

## nav

| Clave | ES actual |
|-------|-----------|
| `nav.primary` | Navegación principal |
| `nav.mobile` | Navegación móvil |
| `nav.home` | Inicio |
| `nav.projects` | Proyectos |

---

## workspace

| Clave | ES actual |
|-------|-----------|
| `workspace.default_title` | Sesión de anidado |
| `workspace.expired` | Esta sesión ya no está disponible. Vuelve a empezar. |

---

## activerecord

| Clave | ES actual |
|-------|-----------|
| `activerecord.models.project.one` | Proyecto |
| `activerecord.models.project.other` | Proyectos |
| `activerecord.models.sheet_stock.one` | Tipo de lámina |
| `activerecord.models.sheet_stock.other` | Tipos de lámina |
| `activerecord.attributes.project.title` | Título |
| `activerecord.attributes.sheet_stock.sort_order` | Orden |
| `activerecord.errors.messages.record_invalid` | La validación falló: %{errors} |
| `activerecord.errors.models.project.attributes.title.blank` | no puede estar en blanco |
| `activerecord.errors.models.project.attributes.base.no_sheet_stocks` | añade al menos un tipo de lámina al inventario |
| `activerecord.errors.models.project.attributes.base.multiple_unlimited_sheet_stocks` | solo se permite un tipo de lámina ilimitado por proyecto |
| `activerecord.errors.models.sheet_stock.attributes.width_mm.blank` | no puede estar en blanco |
| `activerecord.errors.models.sheet_stock.attributes.width_mm.not_a_number` | no es un número |
| `activerecord.errors.models.sheet_stock.attributes.width_mm.greater_than` | debe ser mayor que %{count} |
| `activerecord.errors.models.sheet_stock.attributes.height_mm.blank` | no puede estar en blanco |
| `activerecord.errors.models.sheet_stock.attributes.height_mm.not_a_number` | no es un número |
| `activerecord.errors.models.sheet_stock.attributes.height_mm.greater_than` | debe ser mayor que %{count} |

---

## projects — flashes y estado

| Clave | ES actual |
|-------|-----------|
| `projects.created` | Proyecto creado. |
| `projects.updated` | Proyecto actualizado. |
| `projects.nesting_parameters_updated` | Parámetros de anidado actualizados. |
| `projects.status.draft` | Borrador |
| `projects.status.ready` | Listo |
| `projects.status.processing` | En curso |
| `projects.status.completed` | Completado |
| `projects.status.partial` | Parcial |
| `projects.status.failed` | Fallido |
| `projects.new.title` | Nuevo proyecto |
| `projects.new.setup_title` | Parámetros iniciales |
| `projects.edit.title` | Editar %{title} |

---

## projects — setup welcome (bloque largo)

| Clave | ES actual |
|-------|-----------|
| `projects.setup.missing_dxf` | Sube al menos un archivo DXF antes de continuar. |
| `projects.setup.welcome.intro` | FitLoop coloca tus piezas… *(texto largo)* |
| `projects.setup.welcome.steps_title` | En esta pantalla |
| `projects.setup.welcome.steps` | **Array de 4 strings** (ver es.yml) |

---

## projects — show welcome (bloque largo)

| Clave | ES actual |
|-------|-----------|
| `projects.show.welcome.intro` | *(igual que setup intro)* |
| `projects.show.welcome.steps_title` | En esta pantalla |
| `projects.show.welcome.steps` | **Array de 5 strings** (ver es.yml) |
| `projects.show.session_title` | Tu anidado |
| `projects.show.collapsible_hint` | Pulsa para desplegar |
| `projects.show.sheet_inventory_meta.one` | 1 lámina |
| `projects.show.sheet_inventory_meta.other` | %{count} láminas |
| `projects.show.nesting_parameters_meta` | Separación %{kerf} mm · Margen %{margin} mm |
| `projects.show.nesting_value_mm` | %{value} mm |
| `projects.show.dxf_files_meta.zero` | Sin archivos |
| `projects.show.dxf_files_meta.one` | 1 archivo |
| `projects.show.dxf_files_meta.other` | %{count} archivos |
| `projects.show.dxf_files_title` | Archivos DXF |
| `projects.show.add_dxf_label` | Agregar archivos DXF |
| `projects.show.add_dxf_hint` | Puedes subir más archivos en cualquier momento. |
| `projects.show.source_dxf_detail_summary` | Detalle DXF |
| `projects.show.source_dxf_detail_empty` | Sube un archivo DXF para ver capas y vista previa. |
| `projects.show.dxf_file_layers_meta` | %{selected} de %{total} capas |
| `projects.show.dxf_file_layers_meta_template` | %{selected} de %{total} capas |
| `projects.show.remove_dxf` | Eliminar |
| `projects.show.remove_dxf_confirm` | ¿Eliminar %{filename}? |
| `projects.show.edit` | Editar |
| `projects.show.adjust_setup` | Ajustar parámetros |
| `projects.show.layers` | Capas DXF |
| `projects.show.back` | Inicio |
| `projects.show.manage_title` | Ajustes |

---

## projects — form (alertas y DXF extra)

| Clave | ES actual |
|-------|-----------|
| `projects.form.errors_heading.one` | 1 error impidió guardar |
| `projects.form.errors_heading.other` | %{count} errores impidieron guardar |
| `projects.form.alert_dimensions` | Introduce un ancho y un alto válidos en milímetros. |
| `projects.form.alert_quantity` | Introduce una cantidad de al menos 1… |
| `projects.form.alert_single_unlimited` | Solo se permite un tipo de lámina ilimitado… |
| `projects.form.reorder_sheet` | Arrastrar para reordenar |
| `projects.form.sort_finite_first` | Ordenar: finitos primero |
| `projects.form.sheet_summary` | %{width} × %{height} mm × %{quantity} |
| `projects.form.nesting_settings_legend` | Parámetros de anidado |
| `projects.form.dxf_upload_label` | Archivos DXF |
| `projects.form.dxf_upload_hint` | Elige uno o más archivos DXF… |
| `projects.form.dxf_upload_setup_hint` | Al elegir archivos se listan aquí… |
| `projects.form.dxf_upload_failed` | No se pudieron cargar los archivos DXF… |
| `projects.form.dxf_layers_empty` | No se encontraron capas en este archivo. |
| `projects.form.dxf_upload_resubmit_hint` | Si habías elegido archivos DXF… |
| `projects.form.save_project` | Guardar proyecto |

---

## projects — preview / history / source

| Clave | ES actual |
|-------|-----------|
| `projects.preview.sheet_count.one` | 1 lámina |
| `projects.preview.sheet_count.other` | %{count} láminas |
| `projects.preview.sheet_dimensions` | Lámina %{index}: %{width} × %{height} mm |
| `projects.history.title` | Historial de anidados |
| `projects.history.finished` | finalizado %{time} |
| `projects.source_preview.title` | DXF original (capas seleccionadas) |
| `projects.source_preview.empty` | Selecciona capas para anidar… |
| `projects.source_preview.layer_count.one` | 1 capa visible |
| `projects.source_preview.layer_count.other` | %{count} capas visibles |

---

## nesting — flashes y estados legacy

| Clave | ES actual |
|-------|-----------|
| `nesting.started` | Trabajo de anidado iniciado. |
| `nesting.cancelling` | Cancelación solicitada. |
| `nesting.cancelled` | Anidado cancelado. |
| `nesting.queued` | En cola… |
| `nesting.preparing` | Preparando archivos… |
| `nesting.running` | Ejecutando motor de anidado… |
| `nesting.renest_started` | Reanidado iniciado… |
| `nesting.nest_updated_pieces_started` | Anidado iniciado con las piezas actualizadas… |
| `nesting.nest_updated_pieces_unavailable` | Aún no hay piezas derivadas… |
| `nesting.input_file_missing` | No se encontró el archivo DXF… |
| `nesting.eta_overrun` | Sigue en curso — está tardando más de lo estimado. |
| `nesting.derived_piece.title` | Pieza %{piece_number} — %{suffix} |

---

## nesting — huérfanos / split (resto)

| Clave | ES actual |
|-------|-----------|
| `nesting.orphan_preview.label` | Pieza %{piece_number} sin colocar |
| `nesting.orphan_preview.dimensions` | %{width} × %{height} mm |
| `nesting.orphan_reason.no_sheet_capacity` | Cabe en una lámina pero no quedó espacio |
| `nesting.orphan_reason.unknown` | No se pudo colocar |
| `nesting.orphan_hint.no_sheet_capacity` | Añade más láminas al inventario… |
| `nesting.orphan_hint.unknown` | Revisa el DXF y el inventario… |
| `nesting.split.choose_pending` | Dejar pendiente |
| `nesting.split.regenerate` | Regenerar |
| `nesting.split.accepted` | División aceptada — listo para re-anidar… |
| `nesting.split.accepted_pending_nest` | División aceptada. Las piezas hijas… |
| `nesting.split.not_feasible` | Fitloop no pudo dividir esta pieza… |
| `nesting.split.not_feasible_accept` | Esta vista previa de división no es viable… |
| `nesting.split.manual_mother_still_present` | La geometría de la pieza original sigue… |
| `nesting.split.manual.no_dedup` | Fitloop no modifica tu archivo por ti… |
| `nesting.split.manual.confirm` | He actualizado mis DXF |
| `nesting.split.manual.resolved` | Resolución manual confirmada… |
| `nesting.split.manual.not_manual_state` | Este huérfano no está en resolución manual. |
| `nesting.split.manual.orphan_geometry_missing` | Falta la geometría del huérfano… |
| `nesting.split.badge.resolved` | Resuelto |
| `nesting.split.badge.split_applied` | División aceptada |

---

## nesting_run

| Clave | ES actual |
|-------|-----------|
| `nesting_run.status.processing` | En curso |
| `nesting_run.status.completed` | Completado |
| `nesting_run.status.partial` | Parcial |
| `nesting_run.status.failed` | Fallido |

---

## project_readiness

| Clave | ES actual |
|-------|-----------|
| `project_readiness.heading` | Aún no se puede iniciar el anidado |
| `project_readiness.no_extractable_pieces` | No se encontraron contornos cerrados… |
| `project_readiness.primary_layer_required` | Elige una capa principal para cada DXF… |

---

## project_layers (página índice y upload)

| Clave | ES actual |
|-------|-----------|
| `project_layers.primary_layer.label` | Capa principal |
| `project_layers.primary_layer.tooltip` | Contornos a anidar… |
| `project_layers.primary_layer.selection_hint` | La capa principal define el contorno… |
| `project_layers.auxiliary_layers.label` | Capas asociadas |
| `project_layers.auxiliary_layers.helper` | Grabado, marcas, texto… |
| `project_layers.updated` | Selección de capas guardada. |
| `project_layers.upload.created` | Archivos DXF subidos. |
| `project_layers.upload.removed` | Archivo DXF eliminado. |
| `project_layers.upload.missing` | Elige al menos un archivo DXF. |
| `project_layers.upload.legend` | Subir archivos DXF |
| `project_layers.upload.label` | Archivos DXF |
| `project_layers.upload.submit` | Subir |
| `project_layers.index.title` | Capas — %{title} |
| `project_layers.index.back` | Volver al proyecto |
| `project_layers.index.legend` | Incluir capas en el anidado |
| `project_layers.index.save` | Guardar e iniciar anidado |
| `project_layers.index.empty` | No se encontraron capas… |
| `project_layers.index.files_attached.one` | 1 archivo DXF adjunto |
| `project_layers.index.files_attached.other` | %{count} archivos DXF adjuntos |

---

## date / time (opcional estilo pánico; si no, copiar `es`)

| Clave | Nota |
|-------|------|
| `date.abbr_day_names` | Array 7 |
| `date.day_names` | Array 7 |
| `date.abbr_month_names` | Array 13 (nil + 12 meses) |
| `date.month_names` | Array 13 |
| `date.formats.short` | `%-d %b %Y` |
| `time.formats.short` | `%-d %b %Y %H:%M` |

---

## Ya cubiertas por tu diccionario (~72 claves)

Incluye: `home.index.*`, inventario principal, kerf/margin, DXF upload/apply, preview zone, acciones, fases `nesting.phase.*`, terminales completed/partial/failed/time_limit, huérfanos core, split accept/reject/manual steps, etc.

<task_session>
  <metadata>
    <task_name>Declaración de IVA (formato Hacienda)</task_name>
    <type>Feature</type>
    <req_id>REQ-FIT-ADMIN-001</req_id>
    <roadmap_item>Pending #3 — Declaración de IVA (formato Hacienda)</roadmap_item>
    <depends_on>Admin ventas / reporte de pagos (shipped 2026-05-31)</depends_on>
  </metadata>

  <working_notes>
    ## Context & Goal

    Extender `/admin/ventas` y el export XLSX para producir un **borrador del Formulario 150 — «Impuesto al Valor Agregado»** (sigla TRIBU-CR **IVA01**), alineado al Anexo 1 de la Resolución **MH-DGT-RES-0033-2025** («Formularios y medios para la presentación de declaraciones del impuesto al valor agregado», 22-jul-2025). Sustituye al antiguo D-104 (vigente en TRIBU-CR desde ~oct-2025).

    **No es objetivo v1:** integración TRIBU-CR/API Hacienda, emisión de factura electrónica 4.4, REP, FEC, ni llenar casillas de compras/crédito fiscal desde datos inexistentes en la app.

    ## Tipos de venta Fitloop (SSOT: billing + Payment)

    | Método | Moneda | Cliente | IVA | Casilla Formulario 150 (Sección I) |
    |--------|--------|---------|-----|-------------------------------------|
    | `sinpe_crc` | CRC | CR (`country_code == CR`) | 13% sobre subtotal neto (post-descuento SINPE) | **Total ventas a 13%** (+ **Monto de impuesto a 13%**) |
    | `card_crc` | CRC | CR | 13% sobre subtotal | Idem |
    | `card_usd` | USD | Fuera de CR | Sin IVA (`iva_applicable: false`) | **Total ventas exentas con derecho a crédito pleno** (exportación de servicios; art. 30 RLIVA — marcar «Otras sin IVA con derecho a crédito pleno» en TRIBU-CR) |

    - Producto: **servicio digital** (anidado DXF / suscripción). CAByS fijo `8314200000100`.
    - Snapshots en `payments`: `list_price`, `discount_amount`, `subtotal` (= base imponible CRC), `tax_amount`, `total_amount`, `currency`, `payment_method`.
    - Scope reporting: `Admin::ReportingScope` (excluye `superseded_at`); el export Form 150 **respeta todos los filtros UI** (status, método, búsqueda).
    - Periodo/filtro Form 150: rango libre `start_date`/`end_date` en **`paid_at`** (zona CR), no `created_at`.

    ## Estado actual (baseline)

    Ya existe:
    - Paneles «Declaración CRC» / «Declaración USD» (`DeclarationTotals`)
    - XLSX: Detalle CRC/USD + Resumen Hacienda CRC/USD (`HaciendaSummaryRows` agrupa por día + método)
    - Campos por transacción para facturación manual off-platform

    **Gap:** no hay hoja/casillas con nombres del **Formulario 150** ni totales por tarifa (13% / exentas exportación). Los paneles actuales dicen «Declaración CRC/USD» pero no usan la nomenclatura TRIBU-CR.

    ## Referencias — qué usar y qué descartar

    ### `references/hacienda/MH-DGT-RES-0033-2025.html` — **USAR (norma vigente, SSOT local)**

    Resolución **MH-DGT-RES-0033-2025** (22-jul-2025), publicada en PGRWeb ruta `VIGENTE/2025/19AEA`. Incluye texto normativo + **Anexo 1** (formulario e instrucciones como imágenes PNG embebidas).

    **Artículo 1.1 — nos compete:** contribuyentes IVA en **Régimen Tradicional** autoliquidan en el formulario **«Impuesto al Valor Agregado»** (Anexo 1) vía **TRIBU-CR**. En portal = **Formulario 150 / IVA01**.

    **Artículo 7 — deroga:** DGT-R-36-2019 (D-104) y DGT-R-20-2020.

    **No nos compete (mismo archivo, otros anexos):** Anexo 2 bienes usados B/C (152), Anexo 3-4 agropecuario cuatrimestral/anual (151/152).

    Casillas Sección I (confirmadas vía instrucciones Anexo 1 — layout por tarifa):

    1. **Total ventas a 13%** ← `SUM(subtotal)` CRC succeeded
    2. **Monto de impuesto a 13%** ← `SUM(tax_amount)` CRC
    3. **Total ventas exentas con derecho a crédito pleno** ← exportación servicios USD (`SUM(subtotal)` USD)

    **Nota offline:** el HTML referencia `./MH-DGT-RES-0033-2025_files/*.png`; si la carpeta `_files` no está en repo, las capturas del Anexo 1 no se ven localmente (el texto normativo sí).

    ### Eliminado de `references/hacienda/` (2026-05-31)

    - `Texto Completo acta_ 17A377.html` — resolución DGT-R-36-2019 (D-104), derogada
    - `AYUDA FACTURELE.txt` — tercero desactualizado (citaba D-104; no norma oficial)

    ## Decisiones acordadas (2026-05-31)

    - **D1:** Segundo botón **«Exportar Formulario 150»**; el XLSX de ventas actual **no se toca**.
    - **D2:** Solo archivo XLSX — **sin panel UI** adicional en `/admin/ventas`.
    - **D3:** Fecha imponible = **`paid_at`** (zona CR). Filtro de fechas del export usa `paid_at`, no `created_at`.
    - **D4:** Periodo = **cualquier rango** del filtro (no limitado a mes calendario).
    - **D5:** USD export → **Total ventas exentas con derecho a crédito pleno** (exportación servicios).
    - **D6:** Encabezado (cédula, nombre, Nº formulario) → **celdas vacías** para llenar a mano.
    - **D7:** Alcance = **solo casillas que podemos identificar/rellenar** (Sección I relevante + totales derivados mínimos en IV si aplica), con **etiquetas oficiales** para localizar rápido en TRIBU-CR.
    - **D8:** Export respeta **filtros activos** en `/admin/ventas` (status, método, búsqueda, fechas) — no forzar `succeeded`.
    - **D9:** Dos hojas: **«Soporte ventas»** (detalle editable) + **«Formulario 150»** (casillas con **fórmulas Excel** `SUMIFS`/`SUM` sobre la hoja soporte → si el usuario borra o edita una fila, las casillas se recalculan).
    - **D10:** Compras / crédito fiscal: no incluir bloques extensos; omitir o nota breve «manual en TRIBU-CR».
    - **D11 — Prorrata (Sección III):** **omitir** (v1).

    ## Domain Model

    ### Entity: `Payment` (existente)
    - **Responsibility:** Snapshot inmutable del cobro exitoso.
    - **Invariants:** CRC succeeded ⇒ `tax_amount > 0` (salvo edge futuro); USD succeeded ⇒ `tax_amount == 0`; `subtotal + tax_amount ≈ total_amount`.

    ### Value Object: `Admin::HaciendaForm150Line` (propuesto)
    - **Wraps:** `field_key` (símbolo casilla Form 150), `label` (texto oficial ES del Anexo 1 RES-0033-2025), `amount` (`BigDecimal`), `currency` (`:crc | :usd | nil`), `source` (`:computed | :manual_placeholder`).
    - **Invariants:** Solo casillas en allowlist Fitloop; amounts ≥ 0; CRC 13% lines use CRC scope; export line uses USD scope.

    ### Service: `Admin::ExportForm150Xlsx` (propuesto)
    - **Input:** scope filtrado con **`VentasFilter` adaptado a `paid_at`** + mismos filtros status/método/búsqueda.
    - **Output:** workbook Axlsx con tabla en «Soporte ventas» + fórmulas en «Formulario 150».
    - **Invariants:**
      - Cada fila soporte incluye columnas numéricas: `subtotal`, `tax_amount`, `currency`, `rubro_form150` (derivado: CRC→gravado 13%, USD→exenta crédito pleno).
      - Casillas formulario = fórmulas sobre rango tabular (no valores estáticos), para recálculo al editar soporte.
      - Pagos sin `paid_at` (p. ej. pending): excluidos del rango por fecha o fila con fecha vacía — definir en implementación (recomendación: excluir si `paid_at` NULL y filtro por fechas).

    ## Riesgos / edge cases

    - CR user pagando USD manual (`session[:billing_currency]`) → cae en bucket exportación USD (correcto para IVA).
    - Pagos succeeded sin breakdown snapshot completo (legacy) → migración/backfill o excluir con warning en UI.
    - Descuento SINPE reduce base imponible (correcto: D-104 usa subtotal neto, no list_price).
    - Prorrata: si hay ventas gravadas + exportación exenta en mismo periodo, TRIBU-CR puede ajustar crédito; Fitloop solo entrega ventas, no compras.
    - Validar visualmente contra TRIBU-CR (OVI → Declaraciones → IVA) en QA manual; el HTML local es D-104 derogado.
    - Exportación USD: confirmar con contador que va en «exentas con derecho a crédito pleno» y no en «no sujetas» (exportación servicios = exenta art. 8 LIVA).

    ## Diseño XLSX — Formulario 150 (bloqueado salvo prorrata)

    **Ruta:** `GET /admin/ventas/exportar-formulario-150` — mismos query params que ventas; filtro fecha sobre **`paid_at`**.

    **Nombre archivo:** `formulario-150-{start}-{end}.xlsx` (o timestamp si rango parcial).

    ### Hoja «Soporte ventas» (primera — fuente de verdad)

    Tabla Excel (Axlsx table / rango nombrado) una fila por pago filtrado:

    | Columna | Contenido |
    |---------|-----------|
    | Fecha pago | `paid_at` en CR |
    | Método | label ES |
    | Moneda | CRC / USD |
    | Subtotal | base imponible |
    | IVA 13% | `tax_amount` |
    | Total cobrado | net_collected |
    | Referencia, email, estado, ID | trazabilidad |
    | Rubro Form 150 | «Ventas a 13%» \| «Exentas crédito pleno» (derivado de moneda) |

    El admin puede **borrar filas o corregir montos** antes de declarar.

    ### Hoja «Formulario 150»

    Layout **Casilla (texto oficial) | Monto | Moneda | Notas**:

    - Encabezado: título modelo 150, rango periodo (`{start} — {end}`), cédula/nombre **vacíos**.
    - Sección I — solo filas aplicables a Fitloop:
      - Total ventas a 13% → `=SUMIFS(Soporte!Subtotal, Soporte!Rubro, "Ventas a 13%")`
      - Monto de impuesto a 13% → `=SUMIFS(Soporte!IVA, ...)`
      - Total ventas exentas con derecho a crédito pleno → `=SUMIFS(Soporte!Subtotal, Soporte!Rubro, "Exentas crédito pleno")`
      - Total ventas generales gravadas / Monto impuesto → fórmulas sumando filas gravadas
    - Nota al pie: «Copiar montos a TRIBU-CR Formulario 150 (IVA01). Compras y crédito fiscal: completar en portal.»

    ### Implementación técnica

    - Nuevo `Admin::VentasFilter` option o `Form150VentasFilter` con `date_column: :paid_at`.
    - `Admin::ExportForm150Xlsx` genera fórmulas vía Axlsx (tipo `:formula` en celdas).
    - Request spec: segundo botón, respeta filtros, content-type xlsx.
    - **No** cambiar filtro `created_at` del listado `/admin/ventas` en v1 (solo el export Form 150 usa `paid_at`).

    ## Open question

    _(ninguna — spec cerrado 2026-05-31)_

  </working_notes>

  <implementation_plan>
    <classification>Feature</classification>
    <req_ids>REQ-FIT-ADMIN-001</req_ids>

    <step id="1" status="complete">
      <description>Write failing service spec `spec/services/admin/export_form150_xlsx_spec.rb`: `Admin::ExportForm150Xlsx.call` returns XLSX with sheets «Soporte ventas» and «Formulario 150»; soporte rows for CRC/USD payments; formulario cells contain SUMIFS formulas referencing soporte (not static totals). Tag `[REQ-FIT-ADMIN-001]`.</description>
    </step>
    <step id="2" status="complete">
      <description>Write failing service spec for `Admin::VentasFilter` (or `Form150VentasFilter`) with `date_column: :paid_at`: payment included/excluded by `paid_at` in CR zone, not `created_at`.</description>
    </step>
    <step id="3" status="complete">
      <description>Write failing request spec `GET /admin/ventas/exportar-formulario-150`: admin 200 + xlsx attachment; non-admin 404; honors status/method/search query params; uses `paid_at` date window.</description>
    </step>
    <step id="4" status="complete">
      <description>Extend `Admin::VentasFilter` with optional `date_column` (`:created_at` default, `:paid_at` for Form 150 export). Apply date range on chosen column in CR timezone.</description>
    </step>
    <step id="5" status="complete">
      <description>Implement `Admin::ExportForm150Xlsx`: sheet «Soporte ventas» (tabular detail + `Rubro Form 150` column); sheet «Formulario 150» (official casilla labels for Sección I applicable rows, empty header fields, Excel formulas linking to soporte). Omit Sección III prorrata and compras blocks. Constants for casilla labels aligned to MH-DGT-RES-0033-2025 Anexo 1.</description>
    </step>
    <step id="6" status="complete">
      <description>Add `VentasController#export_form150`, route `GET /admin/ventas/exportar-formulario-150`, reuse filtered scope with `date_column: :paid_at` + existing status/method/search filters.</description>
    </step>
    <step id="7" status="complete">
      <description>Add second button «Exportar Formulario 150» in `app/views/admin/ventas/index.html.erb` preserving `request.query_parameters` (same pattern as export ventas).</description>
    </step>
    <step id="8" status="complete">
      <description>Run targeted specs (`export_form150_xlsx_spec`, `ventas_filter` if new examples, `ventas_spec` export_form150). Fix until green.</description>
    </step>
    <step id="9" status="complete">
      <description>Update `docs/core/SPEC.md` REQ-FIT-ADMIN-001 detail: second XLSX export Form 150, `paid_at` filter, formula-linked sheets. Skip analytics catalog (no telemetry change).</description>
    </step>
  </implementation_plan>
</task_session>

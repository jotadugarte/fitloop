# Analytics and Reporting Contract

Este documento actúa como la fuente de verdad (SSOT) para las superficies de analíticas y reportes de administración en Fitloop. Cualquier cambio en la lógica de negocio, taller, facturación o pagos que afecte estas superficies debe actualizar este contrato y su correspondiente implementación en el mismo PR (Gobernanza Anti-Drift).

---

## 1. Analytics

### Eventos del Sistema
Los siguientes tipos de eventos están definidos y deben coincidir con `config/analytics_event_catalog.yml`:
- `workspace_started`
- `first_dxf_uploaded`
- `project_discarded`
- `nest_completed`
- `account_registered`
- `user_logged_in`
- `user_logged_out`
- `email_confirmed`
- `account_deleted`
- `paywall_viewed`
- `payment_succeeded`
- `payment_failed`
- `download_completed`

### Embudo de Conversión (Funnel Stages)
Las etapas ordenadas del embudo son:
- `workspace_started`
- `first_dxf_uploaded`
- `nest_completed`
- `paywall_viewed`
- `payment_succeeded`
- `download_completed`

### Umbrales de Alerta (`config/analytics.yml`)
Claves de configuración de umbrales utilizadas para el semáforo visual del dashboard:
- `funnel_conversion_min_percent`
- `payment_failure_rate_max_percent`
- `nest_duration_p95_max_seconds`
- `low_priority_events_per_hour`

---

## 2. Ventas

### Columnas de Exportación (Excel / XLSX)

#### Detalle de Pagos (`Admin::ExportPaymentsXlsx::DETAIL_HEADERS`)
Columnas exportadas en la pestaña de detalle:
- `ID`
- `Fecha y Hora`
- `Usuario ID`
- `Email Comprador`
- `Nombre Comprador`
- `Concepto`
- `Identificación SINPE`
- `Teléfono SINPE`
- `Referencia de Compra`
- `ID Intento de Pago (ONVO)`
- `Método de Pago`
- `Estado`
- `Monto Lista`
- `Descuento`
- `Subtotal`
- `Impuesto (IVA 13%)`
- `Total Cobrado`
- `Moneda`
- `Código CAByS`

#### Resumen Hacienda (`Admin::ExportPaymentsXlsx::SUMMARY_HEADERS`)
Columnas exportadas en la pestaña de resumen:
- `Fecha (Día)`
- `Moneda`
- `Método de Pago`
- `Cantidad de Ventas`
- `Total Precio Lista`
- `Total Descuento`
- `Total Subtotal (Base Imponible)`
- `Total IVA 13%`
- `Total Neto Cobrado`

---

## 3. Matriz de Impacto ("si cambias X -> actualiza Y")

| Si cambias X (Origen de Datos) | Debes actualizar Y (Superficie / Reporte) |
| --- | --- |
| Lógica de pagos, estados en ONVO, IVA, CAByS o nuevos flujos | `Admin::ExportPaymentsXlsx`, `Admin::ReportingScope`, `docs/core/ANALYTICS_AND_REPORTING_CONTRACT.md` |
| Nuevas interacciones o eventos en el taller o checkout | `config/analytics_event_catalog.yml`, `Analytics::EventCatalog`, `docs/core/ANALYTICS_AND_REPORTING_CONTRACT.md` |
| Umbrales de conversión o límites de abuso | `config/analytics.yml`, `docs/core/ANALYTICS_AND_REPORTING_CONTRACT.md` |

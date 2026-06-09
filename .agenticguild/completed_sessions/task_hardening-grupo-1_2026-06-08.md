# Session: Hardening Grupo 1

## Requirements
1. **Tests de arquitectura para colas de fondo:**
   - Validar en RSpec que [config/queue.yml](file:///home/jader/proyectos/fitloop/config/queue.yml) tiene una sintaxis de arrays válida para la definición de colas.
   - Validar que cada Job en la aplicación que herede de [ApplicationJob](file:///home/jader/proyectos/fitloop/app/jobs/application_job.rb) esté enrutado a una de las colas configuradas (`default`, `analytics`, `nesting`).

2. **Validación de DXF (Sanitización):**
   - Límite máximo de tamaño de archivo: 10 MB.
   - Comprobación de integridad del formato DXF en Rails en los controladores de subida antes de guardarlo en Active Storage o procesarlo.

3. **Idempotencia de ONVO Webhooks:**
   - Evitar procesamiento duplicado y excepciones concurrentes en [Billing::FulfillPayment](file:///home/jader/proyectos/fitloop/app/services/billing/fulfill_payment.rb) usando bloqueo pesimista en base de datos (`lock!`).
   - Agregar tests de concurrencia e integración para simular webhooks duplicados.

## Decisions
- **D-01:** Establecer el límite de subida del DXF en 10 MB. Esto es seguro frente a ataques DoS y suficiente para anidaciones grandes/complejas.
- **D-02:** Usar ActiveRecord's `lock!` (bloqueo pesimista) sobre el registro del `Payment` al procesar el webhook en `FulfillPayment` o `FailPayment`.

## Domain Model
- **DXF Validation rules:**
  - `Max size`: 10.megabytes.
  - `Format check`: Verify first/last lines or basic structure (e.g. presence of `SECTION` or standard DXF markers).

<implementation_plan>
  <step id="1" status="complete">
    Implement and verify background job queue architecture tests. Create `spec/architecture/background_jobs_spec.rb` to:
    - Parse `config/queue.yml` and verify its syntax and structure.
    - Find all jobs under `app/jobs/` inheriting from `ApplicationJob`.
    - Verify that each job's queue is configured in `config/queue.yml` (e.g. `default`, `analytics`, `nesting`).
  </step>
  <step id="2" status="complete">
    Implement and verify DXF validation (Sanitization):
    - Limit file size to 10 MB.
    - Check file integrity (presence of DXF markers, e.g., SECTION).
    - Add translations.
    - Write failing specs first, then implement.
  </step>
  <step id="3" status="complete">
    Implement and verify ONVO Webhook Idempotency:
    - Prevent duplicate payment fulfillments using database pessimistic locking (`lock!`).
    - Handle concurrent duplicate webhook payloads gracefully.
    - Write concurrent/integration failing tests, then implement.
  </step>
</implementation_plan>

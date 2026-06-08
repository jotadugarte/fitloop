<task_session>
  <metadata>
    <task_name>Script de desarrollo con Solid Queue local</task_name>
    <type>Refactor</type>
    <req_id>[REQ-FIT-QA-001](file:///home/jader/proyectos/fitloop/docs/core/SPEC.md)</req_id>
    <roadmap_item>1. Pruebas, Calidad & Cobertura (CI/CD) - Script de desarrollo con Solid Queue local</roadmap_item>
  </metadata>

  <implementation_plan>
    <step id="1" status="complete">Correr las pruebas existentes (RSpec) para establecer una línea base verde (green baseline) [REQ-FIT-QA-001]</step>
    <step id="2" status="complete">Agregar soporte en `bin/dev` para correr con Solid Queue y Puma integrado usando un flag `--solid` o la variable de entorno `USE_SOLID_QUEUE` [REQ-FIT-QA-001]</step>
    <step id="3" status="complete">Verificar que `config/environments/development.rb` y `config/puma.rb` se activen correctamente cuando se especifica el flag [REQ-FIT-QA-001]</step>
    <step id="4" status="complete">Asegurar la inicialización correcta de las tablas de Solid Queue en el entorno de desarrollo local mediante `bin/rails db:prepare` si es necesario [REQ-FIT-QA-001]</step>
    <step id="5" status="complete">Probar el flujo de anidado de DXF localmente usando Solid Queue en Puma para validar que los trabajos se ejecuten correctamente de forma asíncrona [REQ-FIT-QA-001]</step>
    <step id="6" status="pending">Ejecutar la suite de pruebas completa nuevamente para asegurar que el cambio no haya introducido regresiones [REQ-FIT-QA-001]</step>
  </implementation_plan>

  <working_notes>
    - El roadmap en `docs/ROADMAP.md` tiene exactamente este punto bajo "1. Pruebas, Calidad & Cobertura (CI/CD)" con el nombre: "Script de desarrollo con Solid Queue local".
    - Actualmente, `bin/dev` ejecuta Puma usando Active Job en modo `:async` (en proceso). Esto enmascara problemas de concurrencia, carga de esquemas de colas y fallos de trabajadores distribuidos que sí ocurren en el qualify (donde se usa `solid_queue`).
    - Al habilitar `--solid`, se deben exportar las siguientes variables:
      * `ACTIVE_JOB_QUEUE_ADAPTER=solid_queue`
      * `SOLID_QUEUE_IN_PUMA=1`
    - Puma levantará automáticamente el supervisor de Solid Queue gracias a `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]` in `config/puma.rb`.
    - Otras áreas de discrepancia entre local y qualify/Coolify:
      1. **Almacenamiento Persistente (Active Storage):** En local se guardan en el sistema de archivos directo. En Coolify (Docker), si no hay un volumen persistente mapeado a `/rails/storage`, los DXF subidos y los anidados descargables se perderán al reiniciar el contenedor.
      2. **Bases de datos separadas (Pools de Conexión):** En qualify se usan bases de datos separadas para `primary`, `cache`, `queue` y `cable`. En local se comparte la base de datos `fitloop_development`. Si en qualify la concurrencia es alta y el pool de conexiones en `database.yml` es muy bajo (por defecto 5), la app fallará.
      3. **Action Cable (Solid Cable):** En qualify se requiere que el esquema de Solid Cable esté cargado (`bin/rails db:schema:load:cable`), de lo contrario Action Cable fallará al intentar reportar el progreso del anidado en tiempo real.
      4. **GeoIP / Cloudflare:** El paywall y checkout cambian de CRC (SINPE CRC) a USD (tarjeta) según el país (`CF-IPCountry` de Cloudflare). Si el proxy de Cloudflare está mal configurado en qualify o no se ha descargado el MMDB de GeoLite2 de respaldo, los usuarios fuera o dentro de Costa Rica verán divisas incorrectas.
      5. **Bypass de Webhooks en Cloudflare Zero Trust:** Si la app de qualify está protegida por Cloudflare Access (login obligatorio), ONVO no podrá entregar webhooks de pago exitoso a `/webhooks/onvo` a menos que se configure una regla de bypass para esa ruta exacta.
  </working_notes>
</task_session>

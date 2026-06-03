# Task: Términos y condiciones + Eliminar OAuth (FU-LEGAL-001, FU-LEGAL-002, MVP-AUTH-001)

**Roadmap:** Pending #3 (Pre-live)  
**REQ traceability:** REQ-FIT-AUTH-002, REQ-FIT-BILL-001, REQ-FIT-BILL-002, REQ-FIT-BILL-003  
**Status:** ✅ COMPLETADO  
**Started:** 2026-05-31  
**Pivoted:** 2026-06-01

---

## Decisions locked (2026-05-31, actualizado 2026-06-01)

| # | Decisión |
|---|----------|
| D-L1 | **Sin abogado externo v1** — redacción basada en plantillas públicas (electro.cr, iubenda clickwrap, SaaS prepago) adaptadas al SPEC. Disclaimer: no sustituye asesoría legal. |
| D-L2 | **Solo español** — copy en `es.yml`; no actualizar `en.yml` legal en este epic. |
| ~~D-L3~~ | ~~**Checkbox en ambos checkouts** — plan y descarga suelta.~~ **ANULADA** → ver D-L3b. |
| D-L3b | **⚡ PIVOTE 2026-06-01 — Checkbox SOLO al crear cuenta.** Los Términos y condiciones se aceptan una única vez al registrarse (ya existe en `registrations/new.html.erb`). **No** se muestra ni se valida checkbox en el checkout de plan ni en el checkout de descarga suelta. |
| D-L4 | **Sin reembolsos** — todas las ventas finales una vez confirmado el pago. |
| D-L5 | **Versión legal:** `2026-06-01` (reemplaza `v1-placeholder`). |
| ~~D-L6~~ | ~~Persistencia aceptación checkout: actualizar `users.terms_accepted_at` + `users.terms_version` en cada checkout pagado.~~ **ANULADA** — ya no se toca en checkout. |
| ~~D-L7~~ | ~~Re-aceptación: si `user.terms_version != TermsVersion.current`, checkbox obligatorio antes de pagar.~~ **ANULADA** — flujo de re-aceptación solo aplica en registro/login, fuera del scope de este epic. |
| D-L8 | **Entidad legal:** placeholder `[OPERADOR]` hasta que el titular indique razón social, cédula jurídica y domicilio CR. |
| D-L9 | **⚡ PIVOTE 2026-06-01 — Eliminar OAuth para MVP.** Quitar Google, Apple y Facebook del login/registro. Solo email+contraseña en v1 MVP. Afecta: Gemfile, initializer, User model, OmniauthCallbacksController, `lib/auth/omniauth_providers.rb`, vistas Devise. |
| D-L10 | **Preservar estructura, no borrar datos.** Las columnas `users.provider`, `users.uid` quedan en el schema (migraciones ya aplicadas); solo se desactiva el flujo UI + gems. Permite reactivar OAuth en v2 sin migración. |
| D-L11 | **⚡ 2026-06-01 — Contenido legal en Markdown.** Los textos de T&C y Política de privacidad viven en `app/content/legal/terminos.md` y `privacidad.md`. El controlador los lee y renderiza con `redcarpet`. Editar el `.md` + deploy = refleja de inmediato. El historial de cambios queda en Git. `es.yml` **no** almacena el cuerpo de los textos legales (solo claves cortas de UI). |


---

## Open questions (remaining)

- [ ] Datos del operador legal (nombre, cédula, domicilio, correo soporte) para insertar en §1.
- [ ] ¿Emitir factura electrónica al cliente en v1? (fuera de copy T&C por ahora; mencionar solo IVA en checkout).
- [ ] Privacidad: ampliar con FU-LEGAL-003 en deploy checklist; borrador mínimo incluido abajo.

---

## Draft: Términos de servicio Fitloop

**Versión:** `2026-06-01`  
**Idioma:** español (Costa Rica)  
**Destino i18n:** claves `legal.terms.sections.*` o HTML parcial en vista (decisión en implementation plan).

---

### Texto propuesto (publicar en `/terminos`)

**TÉRMINOS DE SERVICIO DE FITLOOP**

Última actualización: 1 de junio de 2026  
Versión: 2026-06-01

#### 1. Identificación del servicio

Fitloop («**Fitloop**», «**el Servicio**», «**nosotros**») es una aplicación web que permite cargar archivos DXF, configurar láminas y ejecutar un proceso de anidado (nesting) para obtener un DXF anidado listo para corte.

El Servicio es operado por **[OPERADOR — completar razón social, cédula jurídica o identificación y domicilio en Costa Rica]** («**el Operador**»).

Al registrarse, navegar, usar el taller, comprar un plan o pagar una descarga, usted («**Usuario**», «**usted**») acepta estos Términos de Servicio y nuestra [Política de privacidad](/privacidad). Si no está de acuerdo, no utilice el Servicio ni realice pagos.

#### 2. Descripción del servicio

Fitloop ofrece:

- Un **taller en línea** para cargar DXF, definir inventario de láminas, seleccionar capas y ejecutar anidados.
- **Vista previa** del resultado de anidado (sin costo).
- **Descarga del DXF anidado** mediante pago o beneficio de plan, según corresponda.

El anidado es un servicio **digital** que se ejecuta en nuestros servidores. Los tiempos de procesamiento dependen de la complejidad del proyecto y pueden estar sujetos a un límite de tiempo configurado.

#### 3. Cuenta de usuario

3.1. Para pagar o usar ciertas funciones debe crear una cuenta con correo verificado.

3.2. Usted es responsable de la confidencialidad de sus credenciales y de toda actividad en su cuenta.

3.3. Debe proporcionar información veraz. Nos reservamos el derecho de suspender cuentas por uso indebido, fraude o incumplimiento de estos Términos.

3.4. **Eliminación de cuenta:** puede eliminar su cuenta en cualquier momento. La eliminación es **definitiva** y conlleva la pérdida del acceso al taller, historial de pagos y, si aplica, **todo beneficio restante de un plan activo** (incluidas descargas no utilizadas). No hay reembolso por saldo o tiempo no consumido.

#### 4. Proyectos y sesión de trabajo

4.1. Los proyectos de anidado en Fitloop son **efímeros**: están vinculados a su sesión de navegador y pestaña de trabajo. Si cierra el navegador, cambia de dispositivo o pierde la sesión, **puede perder el acceso al proyecto en curso** y deberá volver a cargar sus archivos y ejecutar un nuevo anidado.

4.2. Fitloop **no garantiza** almacenamiento permanente de sus archivos DXF ni de configuraciones de taller más allá de lo estrictamente necesario para prestar el Servicio.

#### 5. Productos de pago

Fitloop ofrece dos tipos de compra:

**A) Descarga suelta** — pago único por la descarga de un DXF anidado de una ejecución de anidado concreta.

**B) Plan prepagado** — pago único por un **periodo de acceso** de 1, 2 o 4 meses calendario (según el plan elegido), con un cupo mensual de descargas incluidas.

**Importante:** los planes **no son suscripciones con cargo automático recurrente**. Cada plan es un **prepago por periodo**. Fitloop **no** debitará su tarjeta ni realizará cobros automáticos al vencer el plan. Para continuar después del vencimiento debe **comprar un nuevo plan manualmente**.

#### 6. Planes prepagados — condiciones (FU-LEGAL-002)

6.1. **Cupo mensual:** durante cada mes calendario dentro de su periodo activo, tiene derecho a **50 (cincuenta) descargas incluidas** del DXF anidado. El cupo **se reinicia al inicio de cada mes calendario** mientras su plan esté vigente (por ejemplo, un plan de 2 meses incluye hasta 50 descargas en el mes 1 y hasta 50 en el mes 2).

6.2. **Inicio y fin del plan:** el plan comienza en el momento del pago confirmado. Finaliza al **último instante del día natural** correspondiente a la duración contratada (1, 2 o 4 meses), calculado según la **zona horaria registrada en su cuenta**.

6.3. **Extensión:** si compra un plan adicional mientras tiene uno activo, el nuevo periodo **se suma al final** del plan vigente (no reinicia la fecha desde el día de la compra).

6.4. **Sin periodo de gracia:** al vencer el plan, **pierde de inmediato** el beneficio de descargas incluidas. Debe adquirir un nuevo plan o pagar descargas sueltas para continuar descargando.

6.5. **Descargas incluidas en el plan:**
   - Solo aplican mientras el plan esté activo y quede cupo en el mes.
   - **No incluyen retención de 24 horas** en «Mis pagos».
   - Si pierde la sesión de taller o el proyecto efímero, **debe volver a anidar**; no podrá re-descargar un anidado anterior solo porque formaba parte de su plan.

6.6. **Cupo agotado — descarga con tarifa reducida:** si agotó las 50 descargas del mes calendario en curso pero su plan sigue activo, puede comprar **descargas sueltas adicionales** al **50 % del precio normal** de descarga suelta (tarifa de excedente). Los precios vigentes se muestran en el paywall y checkout antes del pago.

6.7. **Un plan activo por cuenta:** solo puede tener un plan activo a la vez; las compras adicionales extienden ese plan según §6.3.

#### 7. Descarga suelta — condiciones

7.1. Al pagar una descarga suelta obtiene derecho a descargar el DXF anidado de **esa ejecución de anidado específica**.

7.2. **Retención 24 horas:** tras un pago exitoso, conservamos una copia del archivo en «Mis pagos» durante **24 horas** desde la confirmación del pago, para que pueda descargarlo aunque pierda la sesión del taller. **Pasadas 24 horas**, el archivo deja de estar disponible para descarga.

7.3. Las descargas sueltas **no son reembolsables** una vez confirmado el pago y habilitada la descarga o iniciada la retención.

#### 8. Precios, impuestos y facturación

8.1. Los precios se muestran en el paywall y checkout **antes** de confirmar el pago. Pueden expresarse en colones costarricenses (CRC) o dólares estadounidenses (USD) según su ubicación y método de pago.

8.2. **Costa Rica:** los precios en CRC pueden mostrar un precio de referencia (tarjeta) y un precio con descuento por **SINPE Móvil**, según se indique en pantalla. En checkout se desglosa el subtotal, descuento SINPE (si aplica) e **IVA del 13 %** sobre la base imponible correspondiente.

8.3. **Fuera de Costa Rica (USD):** no se calcula ni cobra IVA costarricense.

8.4. Los precios pueden actualizarse; el precio aplicable es el mostrado **en el momento del checkout** y congelado en su carrito hasta que lo reemplace o complete la compra.

#### 9. Pagos

9.1. Los pagos se procesan mediante **ONVO Pay** (tarjeta de crédito/débito en CRC o USD, o SINPE Móvil en CRC). Al pagar, también aplican los términos del procesador de pagos en la medida que correspondan.

9.2. Un pago **no se considera completado** hasta recibir confirmación del procesador (webhook o equivalente). Hasta entonces, no se otorgan descargas ni beneficios de plan.

9.3. **SINPE Móvil:** si inicia un pago SINPE, debe transferir el monto **exacto** indicado. Fitloop puede bloquear temporalmente cambios en el taller mientras un pago SINPE está pendiente de confirmación.

9.4. Fitloop **no almacena** el número completo de su tarjeta; el procesador de pagos gestiona los datos sensibles de tarjeta.

#### 10. Política de reembolsos

10.1. **Todas las ventas son finales.** No ofrecemos reembolsos, devoluciones ni créditos por:

- cambio de opinión;
- resultados de anidado distintos a lo esperado (salvo fallo técnico imputable al Servicio según §11);
- pérdida de sesión, proyecto efímero o falta de uso del cupo del plan;
- eliminación voluntaria de cuenta;
- vencimiento del plan o del periodo de retención de 24 horas.

10.2. Al completar un pago usted reconoce que el servicio digital comienza de forma inmediata o casi inmediata y **renuncia expresamente a solicitar reembolso**, en la máxima medida permitida por la ley aplicable.

#### 11. Disponibilidad, calidad y limitación de responsabilidad

11.1. Fitloop se ofrece «**tal cual**» y «**según disponibilidad**». No garantizamos que el anidado sea óptimo para todo caso de producción, ni ausencia total de errores.

11.2. Usted es responsable de **verificar** el DXF resultante antes de usarlo en corte, producción o instalación.

11.3. Fitloop **no se hace responsable** por daños indirectos, lucro cesante, pérdida de datos, material desperdiciado o decisiones de producción basadas en los archivos generados.

11.4. En cualquier caso, la responsabilidad total del Operador frente a usted por un hecho concreto **no excederá el monto que usted pagó** por la transacción que dio origen al reclamo.

#### 12. Propiedad intelectual y uso permitido

12.1. Fitloop, su software, marca e interfaz son propiedad del Operador o sus licenciantes.

12.2. Usted conserva la propiedad de los archivos DXF que cargue. Nos otorga una licencia limitada para procesarlos únicamente a fin de prestar el Servicio.

12.3. Queda prohibido: ingeniería inversa del Servicio, uso automatizado abusivo, reventa del Servicio, intentos de eludir el paywall o interferir con la infraestructura.

#### 13. Aceptación de términos en el checkout

13.1. Antes de procesar cualquier pago (plan o descarga suelta), debe marcar la casilla de aceptación de estos Términos y la Política de privacidad vigentes.

13.2. Si publicamos una **nueva versión material** de estos Términos, deberá aceptarla antes de su próximo pago.

#### 14. Modificaciones

Podemos actualizar estos Términos publicando una nueva versión en `/terminos` con fecha de vigencia. El uso continuado del Servicio o un nuevo pago después de la publicación implica aceptación de la versión vigente.

#### 15. Ley aplicable y jurisdicción

Estos Términos se rigen por las **leyes de la República de Costa Rica**. Cualquier controversia se someterá a los **tribunales competentes de Costa Rica**, salvo norma imperativa en contrario.

#### 16. Contacto

Consultas sobre estos Términos: **[correo de soporte — completar]**.

---

### Nota editorial (no publicar)

- Basado en estructura de [electro.cr T&C digitales](https://electro.cr/es/informacion/terminos-condiciones-generales), guía clickwrap [iubenda](https://www.iubenda.com/es/blog/plantilla-de-politica-de-reembolso-que-su-empresa-necesita/), y reglas SPEC Fitloop (D27–D34, D50, D54).
- **No es asesoría legal.** Revisión por abogado CR recomendada antes de go-live comercial.

---

## Draft: Política de privacidad (mínima v1 — FU-LEGAL-001)

**Versión:** `2026-06-01`  
_(Ampliación analytics → FU-LEGAL-003 en deploy checklist)_

#### Resumen

Recopilamos datos necesarios para operar cuentas, procesar pagos y prestar el taller. No vendemos sus datos personales.

#### Datos que recopilamos

- **Cuenta:** nombre, correo, contraseña (hash), zona horaria.
- **Pago:** nombre y correo del comprador, método de pago, montos e identificadores de transacción (no almacenamos CVV ni número completo de tarjeta).
- **Taller:** metadatos de proyectos (no conservamos indefinidamente sus DXF salvo retención temporal de descarga pagada).
- **Técnicos:** dirección IP, agente de navegador, cookies de sesión e idioma.

#### Finalidades

Prestar el Servicio, autenticación, facturación, soporte, seguridad y cumplimiento legal.

#### Conservación

Conservamos datos de cuenta mientras mantenga la cuenta. Archivos de descarga suelta retenidos **24 horas** tras el pago. Datos de pago según obligaciones contables y fiscales.

#### Sus derechos

Puede solicitar acceso, rectificación o eliminación contactando **[correo — completar]**. Eliminar la cuenta implica borrado del acceso según los Términos.

#### Transferencias

Usamos procesadores de pago (ONVO) que pueden tratar datos fuera de Costa Rica bajo sus propias políticas.

#### Cambios

Publicaremos actualizaciones en `/privacidad` con nueva versión.

---

## Domain Model (updated)

### TermsVersion
- **VO:** `TermsVersion` → `"2026-06-01"`
- **Invariants:** `TermsVersion.current` == versión mostrada en `/terminos`; bump en cambios materiales.

### CheckoutTermsAcceptance (via User columns)
- **Responsibility:** Prueba de aceptación vigente al pagar.
- **Invariants:** `checkout` blocked unless checkbox + `terms_version == current` (or checkbox sets both on submit); `terms_accepted_at` refreshed on successful payment initiation or on form submit (TBD in plan — recommend on pay submit before gateway).
- **Persistence:** `users.terms_accepted_at`, `users.terms_version` (existing).

---

## Implementation notes (for plan — not executed)

1. Replace `legal.terms.body` monolith with structured sections in `es.yml` OR partial `_terms_sections.html.erb`.
2. `TermsVersion::CURRENT = "2026-06-01"`.
3. Shared partial `_checkout_terms_acceptance.html.erb` in plan + single checkout forms (simulate + ONVO).
4. Controller validation: reject pay without `terms_accepted=1`; update user terms fields.
5. Remove `placeholder_notice` from terms page when live.
6. Request specs: checkout without checkbox → 422; with checkbox → proceeds.
7. **No** `en.yml` legal update (D-L2).

---

## Implementation plan

<implementation_plan>
  <meta>
    <title>FU-LEGAL-001/002 — T&C en registro + páginas legales | MVP-AUTH-001 — Eliminar OAuth</title>
    <type>feature</type>
    <language>ruby</language>
    <primary_stack>Rails 8 + Hotwire + i18n YAML + Devise</primary_stack>
    <anchors>
      <anchor>docs/core/SYSTEM_ARCHITECTURE.md</anchor>
      <anchor>docs/core/SPEC.md (REQ-FIT-BILL-001/002/003, REQ-FIT-AUTH-002)</anchor>
    </anchors>
  </meta>

  <scope>
    <in_scope>
      <item>**[T&C]** Actualizar páginas `/terminos` y `/privacidad` con copy real (ya aprobado, versión `2026-06-01`).</item>
      <item>**[T&C]** Versionar términos con `TermsVersion.current = "2026-06-01"` (reemplaza placeholder).</item>
      <item>**[T&C]** Confirmar que el checkbox de aceptación YA existe en `registrations/new.html.erb` (solo se verifica, no se agrega).</item>
      <item>**[OAUTH]** Eliminar gems `omniauth`, `omniauth-google-oauth2`, `omniauth-facebook`, `omniauth-apple`, `omniauth-rails_csrf_protection` del `Gemfile`.</item>
      <item>**[OAUTH]** Quitar el initializer `config/initializers/devise_omniauth.rb` (o vaciarlo).</item>
      <item>**[OAUTH]** Quitar `:omniauthable` y `omniauth_providers` del módulo Devise en `User`; eliminar `User.from_omniauth`.</item>
      <item>**[OAUTH]** Eliminar `Users::OmniauthCallbacksController` o dejarlo vacío sin rutas.</item>
      <item>**[OAUTH]** Quitar `omniauth_callbacks:` del `devise_for` en `config/routes.rb`.</item>
      <item>**[OAUTH]** Quitar `lib/auth/omniauth_providers.rb` y la referencia en `application_helper.rb`.</item>
      <item>**[OAUTH]** Quitar el partial `_oauth_buttons.html.erb` y su `render` en sessions/new y registrations/new; quitar el separador "o continuar con email" si queda huérfano.</item>
      <item>**[OAUTH]** Quitar el partial del merge de cuentas OAuth si existe (ruta `fusionar_cuenta_path`).</item>
    </in_scope>
    <out_of_scope>
      <item>Checkbox de T&C en checkout (anulado por D-L3b).</item>
      <item>Persistencia de terms_version en checkout (anulado por D-L6).</item>
      <item>Re-aceptación de términos en checkout (anulado por D-L7).</item>
      <item>Asesoría legal externa / validación MEIC formal.</item>
      <item>Factura electrónica al cliente final (mencionar IVA en checkout es suficiente para v1).</item>
      <item>FU-LEGAL-003 completo (analytics/retención/archivo frío) — queda en Deploy checklist.</item>
      <item>Traducción EN.</item>
      <item>Eliminar columnas `users.provider` / `users.uid` del schema (D-L10: se conservan para reactivar OAuth en v2).</item>
      <item>Reimplementar OAuth en v2.</item>
    </out_of_scope>
  </scope>

  <deliverables>
    <deliverable>Archivos `app/content/legal/terminos.md` y `privacidad.md` con copy `2026-06-01` (editables directamente).</deliverable>
    <deliverable>Gem `redcarpet` añadida y helper `render_markdown` en `ApplicationHelper`.</deliverable>
    <deliverable>Páginas `/terminos` y `/privacidad` leen del `.md` en tiempo de request, sin placeholder.</deliverable>
    <deliverable>`TermsVersion::CURRENT = "2026-06-01"` funcionando.</deliverable>
    <deliverable>Login y registro solo por email+contraseña: sin botones OAuth en UI.</deliverable>
    <deliverable>Sin gems ni código OmniAuth en el proyecto (bundle clean).</deliverable>
    <deliverable>Tests relevantes verdes (sin referencias a OmniAuth en specs).</deliverable>
  </deliverables>

  <steps>
    <!-- ─── TESTS PRIMERO (TDD — Feature rule) ─── -->
    <step id="T0a" status="complete">Escribir specs que fallen ahora y pasen al final — T&C:
      <substep>Request spec: GET `/terminos` → 200, body NO contiene `placeholder` ni `placeholder_notice`.</substep>
      <substep>Request spec: GET `/privacidad` → 200, body NO contiene `placeholder`.</substep>
      <substep>Model spec (o unit): `TermsVersion::CURRENT == "2026-06-01"` (falla mientras siga siendo `v1-placeholder`).</substep>
      Confirmar que estos specs fallan antes de tocar código (red).</step>

    <step id="T0b" status="complete">Escribir specs que fallen ahora y pasen al final — OAuth removal:
      <substep>Request spec: GET `/users/sign_in` → 200, body no contiene "Google", "Apple", "Facebook" ni `oauth-providers`.</substep>
      <substep>Request spec: GET `/users/sign_up` → ídem.</substep>
      <substep>Routing spec: `route_to` de cualquier ruta `omniauth` → raise `ActionController::RoutingError` (no existe).</substep>
      Confirmar que estos specs fallan antes de tocar código (red).</step>

    <!-- ─── BLOQUE A: T&C legal pages ─── -->
    <step id="A1" status="complete">Leer secciones relevantes de `docs/core/SPEC.md` (REQ-FIT-BILL-001/002/003, REQ-FIT-AUTH-002) para confirmar que el copy aprobado no contradice reglas del SPEC (cupo, overage, no gracia, proyectos efímeros, retención 24h).</step>

    <step id="A2" status="complete">Actualizar `TermsVersion::CURRENT` a `"2026-06-01"` en el lugar donde esté definido (buscar `TermsVersion` en `app/` y `lib/`).</step>

    <step id="A3" status="complete">Agregar gem `redcarpet` al `Gemfile` (sin grupo, para producción) y correr `bundle install`.
      <substep>Crear helper `render_markdown(text)` en `app/helpers/application_helper.rb` usando `Redcarpet::Markdown` con opciones: `html: true, hard_wrap: true, autolink: true`.</substep>
    </step>

    <step id="A4" status="complete">Crear directorio `app/content/legal/` y escribir los dos archivos Markdown con el copy aprobado (versión `2026-06-01`):
      <substep>`app/content/legal/terminos.md` — texto completo de Términos de Servicio (§1–§16).</substep>
      <substep>`app/content/legal/privacidad.md` — texto completo de Política de privacidad.</substep>
    </step>

    <step id="A5" status="complete">Actualizar las vistas legales para leer y renderizar los archivos `.md`:
      <substep>En `app/views/legal/terminos.html.erb` (o equivalente): reemplazar el `t("legal.terms.body")` por `raw render_markdown(File.read(Rails.root.join("app/content/legal/terminos.md")))`.</substep>
      <substep>Ídem para `privacidad.html.erb`.</substep>
      <substep>Quitar o vaciar las claves `legal.terms.body` y `legal.privacy.body` de `es.yml` (conservar solo claves de UI cortas: título, link, etc.).</substep>
      <substep>Quitar `legal.placeholder_notice` y su render en las vistas.</substep>
    </step>

    <step id="A6" status="complete">Verificar que `registrations/new.html.erb` ya renderiza `_terms_acceptance` y que el checkbox funciona correctamente (solo confirmar, no agregar).</step>

    <!-- ─── BLOQUE B: Eliminar OAuth ─── -->
    <step id="B1" status="complete">
      Eliminar las 5 gems OAuth del `Gemfile`:
      <substep>`gem "omniauth", "~> 2.1"`</substep>
      <substep>`gem "omniauth-google-oauth2", "~> 1.2"`</substep>
      <substep>`gem "omniauth-facebook", "~> 10.0"`</substep>
      <substep>`gem "omniauth-apple", "~> 1.3"`</substep>
      <substep>`gem "omniauth-rails_csrf_protection", "~> 1.0"`</substep>
      Luego ejecutar `bundle install` para actualizar `Gemfile.lock`.
    </step>

    <step id="B2" status="complete">Eliminar (o vaciar con comentario explicativo) `config/initializers/devise_omniauth.rb`. No debe quedar ninguna llamada `config.omniauth`.</step>

    <step id="B3" status="complete">
      En `app/models/user.rb`:
      <substep>Quitar `:omniauthable` del listado de módulos Devise y quitar `omniauth_providers: %i[google_oauth2 facebook apple]`.</substep>
      <substep>Eliminar `User.from_omniauth` (método de clase).</substep>
      <substep>Eliminar cualquier atributo virtual o accessor relacionado con OAuth si existe.</substep>
    </step>

    <step id="B4" status="complete">Eliminar (o dejar como stub comentado) `app/controllers/users/omniauth_callbacks_controller.rb`. Si se elimina el archivo, asegurarse de que no rompa autoload.</step>

    <step id="B5" status="complete">
      En `config/routes.rb`:
      <substep>Quitar `omniauth_callbacks: "users/omniauth_callbacks"` de `devise_for`.</substep>
      <substep>Quitar ruta `fusionar_cuenta_path` y su controlador/vista asociada si existe (buscar `fusionar_cuenta`).</substep>
    </step>

    <step id="B6" status="complete">
      Eliminar `lib/auth/omniauth_providers.rb` (y directorio `lib/auth/` si queda vacío).
      Quitar `user_omniauth_authorize_path` de `app/helpers/application_helper.rb`.
    </step>

    <step id="B7" status="complete">
      En las vistas Devise:
      <substep>Eliminar `app/views/devise/shared/_oauth_buttons.html.erb`.</substep>
      <substep>Quitar `render "devise/shared/oauth_buttons"` de `sessions/new.html.erb` y `registrations/new.html.erb`.</substep>
      <substep>Quitar el párrafo separador `auth-page__divider` ("o continuar con email") si queda huérfano en ambas vistas.</substep>
      <substep>Quitar el `data-controller="timezone-capture"` del `div.oauth-providers` si ese JS solo servía para capturar la zona horaria para OAuth (verificar si se usa también en el form de registro por email).</substep>
    </step>

    <step id="B8" status="complete">Buscar y eliminar vistas, helpers y clases asociadas al merge de cuentas OAuth (`fusionar_cuenta`, `Accounts::OauthCollision`, etc.) si existen.</step>

    <step id="B9" status="complete">Buscar en `spec/` todas las referencias a `omniauth`, `oauth`, `google_oauth2`, `facebook`, `apple` (OmniAuth mocks, shared examples, etc.) y eliminarlos o comentarlos.</step>

    <!-- ─── BLOQUE C: Verificación ─── -->
    <step id="C1" status="complete">Correr `bundle exec rails routes` y verificar que no aparezcan rutas `omniauth` ni `fusionar_cuenta`.</step>

    <step id="C2" status="complete">Correr `bundle exec rspec spec/requests/ spec/models/user_spec.rb` (o equivalente) y dejar la suite verde.</step>

    <step id="C3" status="complete">QA manual: visitar `/users/sign_in` y `/users/sign_up` — confirmar que solo aparece el formulario email+contraseña sin botones OAuth.</step>

    <step id="C4" status="complete">QA manual: visitar `/terminos` y `/privacidad` — confirmar que muestran el copy `2026-06-01` sin aviso de placeholder.</step>
  </steps>

  <test_plan>
    <item>**Unit:** `User` no responde a `.from_omniauth` ni a métodos OAuth.</item>
    <item>**Request spec:** GET `/users/sign_in` y `/users/sign_up` → 200, sin mencionar "Google", "Facebook", "Apple".</item>
    <item>**Request spec:** POST `/users/sign_up` sin `terms_accepted=1` → error de validación (comportamiento actual ya testeado).</item>
    <item>**Request spec:** GET `/terminos` → 200, sin `placeholder_notice`.</item>
    <item>Correr `bundle exec rspec` completo y dejar verde.</item>
  </test_plan>

  <acceptance_criteria>
    <criterion>Los textos de `/terminos` y `/privacidad` muestran la versión `2026-06-01`, sin texto placeholder.</criterion>
    <criterion>El login y registro muestran SOLO el formulario email+contraseña. Sin botones ni sección OAuth.</criterion>
    <criterion>No existen referencias a `omniauth` en `Gemfile`, initializers, modelos, controladores ni vistas (salvo comentarios históricos opcionales).</criterion>
    <criterion>`bundle install` pasa sin advertencias de gems OAuth faltantes.</criterion>
    <criterion>Los tests pasan.</criterion>
    <criterion>No hay checkbox de T&C en el checkout (solo en el formulario de registro).</criterion>
  </acceptance_criteria>
</implementation_plan>

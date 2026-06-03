# Task: modulusloop-platform

**Created:** 2026-06-02  
**Status:** Discovery — Phase 1  
**Classification:** Feature (Major — Platform Rebrand + New Home)  

---

## Owner Request

> La plataforma se llamará **moduSLoop**. La pantalla de inicio será una pantalla de tarjetas donde el estudiante verá las herramientas disponibles. **FitLoop** es una de esas herramientas (distribución de láminas DXF). En el futuro habrá otras herramientas. Al hacer clic en FitLoop, el usuario va al taller (flujo actual). El usuario/contraseña es de **toda la plataforma moduSLoop**, no de FitLoop solo.

---

---

## Decision Log

| ID | Decisión | Fuente | Fecha |
|----|----------|--------|-------|
| D1 | **Billing sin cambios.** El sistema de pagos (Checkout, Cart, Planes, ONVO) se mantiene exactamente igual, atado a fiTLoop. | Owner | 2026-06-02 |
| D2 | **Nombres exactos:** plataforma = `moduSLoop`; herramienta DXF = `fiTLoop`; herramienta próxima = `synCLoop`. Toda instancia de "Fitloop", "fitloop", "FitLoop" en código/i18n/comentarios se reemplaza por `fiTLoop`. | Owner | 2026-06-02 |
| D3 | **Tarjeta fiTLoop → `/taller` directo.** El clic en la tarjeta lleva a `workshop_path`, no a `/empezar`. | Owner | 2026-06-02 |
| D4 | **synCLoop está "próximamente"** — tarjeta visible pero deshabilitada. Tiene logo propio (`images/logo-syncloop.png`). | Owner | 2026-06-02 |
| D5 | **Assets disponibles:** `images/logo-modusloop.png`, `images/icono-modusloop.png`, `images/logo-syncloop.png`, `images/fitloop-logo.png` (minilogo: `images/fitloop-minilogo.png`). | Codebase | 2026-06-02 |
| D6 | **Relación fiTLoop ↔ moduSLoop en la UI:** fiTLoop se presenta como "herramienta del ecosistema moduSLoop". En el taller el usuario verá el logo de fiTLoop, pero la plataforma (home, auth, nav, favicon, `<title>`) usa moduSLoop. | Owner + análisis | 2026-06-02 |

| D7 | **Logo en auth = moduSLoop.** Las pantallas de login/registro/contraseña usan `logo-modusloop.png`. Favicon/icono de toda la plataforma = `icono-modusloop.png`. El logo de `fiTLoop` (`logo.png`) permanece en el taller y en la tarjeta de la home. | Owner (Opción A) | 2026-06-02 |

**Rename adicional en la tabla de scope §3:** `_fitloop_dialog` y clases CSS `fitloop-dialog` son nombres de componentes internos — **no son nombres de marca**, se conservan tal cual.

---

**Spec cerrado. Listo para `start-task`.**

---

<implementation_plan>

<step id="1" status="pending">
**Publish assets:** Copy new logos to `public/images/`:
- `images/logo-modusloop.png` → `public/images/logo-modusloop.png`
- `images/icono-modusloop.png` → `public/images/icono-modusloop.png`
- `images/logo-syncloop.png` → `public/images/logo-syncloop.png`
- `images/fitloop-logo.png` → `public/images/fitloop-logo.png` (keep existing `logo.png` alias for now, add new name)
- `images/fitloop-minilogo.png` → `public/images/fitloop-minilogo.png` (keep existing `minilogo.png` alias)
</step>

<step id="2" status="pending">
**i18n — application.name rename + fiTLoop brand sweep:**
- `config/locales/es.yml`: `application.name` → `"moduSLoop"`, `dialog_title` → `"moduSLoop"`. Replace all user-visible `"Fitloop"` / `"FitLoop"` brand text → `"fiTLoop"`.
- `config/locales/en.yml`: same sweep.
- `config/locales/es_panic.yml`: same sweep.
- **Scope:** only user-visible strings (values), not YAML keys.
</step>

<step id="3" status="pending">
**Layout: favicons + title → moduSLoop:**
- `app/views/layouts/application.html.erb`: change favicon `href` to `/images/icono-modusloop.png`, apple-touch-icon same.
- `app/views/layouts/minimal.html.erb`: same favicon update.
- `app/views/layouts/admin.html.erb`: change `<title>Fitloop Admin</title>` → `<title>moduSLoop Admin</title>`; "Fitloop Admin" link text → "moduSLoop Admin"; "← Ir a Fitloop" → "← Ir a moduSLoop".
- `app/views/pwa/manifest.json.erb`: `name` → "moduSLoop", `description` → "moduSLoop — Herramientas para estudiantes.", icon `src` → `/images/icono-modusloop.png`.
</step>

<step id="4" status="pending">
**Auth layout: moduSLoop logo on login/register/password screens:**
- `app/views/devise/shared/_auth_page.html.erb`: change `image_tag "/images/logo.png"` → `image_tag "/images/logo-modusloop.png"`.
- Ensure `alt` uses `t("application.name")` (will now be "moduSLoop" after step 2).
</step>

<step id="5" status="pending">
**Home page: full moduSLoop Hub redesign:**
- `app/views/home/index.html.erb`: Replace landing hero with tool hub grid. Two cards:
  1. **fiTLoop** — logo `fitloop-logo.png`, tagline (distribución DXF), link to `workshop_path`.
  2. **synCLoop** — logo `logo-syncloop.png`, badge "Próximamente", disabled (no link, `aria-disabled`).
- New i18n keys in `es.yml` / `en.yml` for hub: `home.hub.title`, `home.hub.fitloop_tagline`, `home.hub.syncloop_tagline`, `home.hub.coming_soon`.
</step>

<step id="6" status="pending">
**CSS: new tool hub styles in `application.css`:**
- Add `.tool-hub`, `.tool-hub__grid`, `.tool-card`, `.tool-card--disabled`, `.tool-card__logo`, `.tool-card__name`, `.tool-card__tagline`, `.tool-card__badge` classes.
- Remove or repurpose `.landing-hero` styles since the home page no longer uses them.
</step>

<step id="7" status="pending">
**Remaining brand text in views:**
- `app/views/layouts/admin.html.erb`: already covered in step 3.
- Any remaining `"Fitloop"` literal strings in `.erb` views (e.g. paywall aside logos currently use `/images/logo.png` with `alt: t("application.name")` — these already use i18n so the alt text updates automatically via step 2; no template change needed).
- `public/icon.png`: optionally replace with moduSLoop icon (low-priority, no test coverage; do if feasible).
</step>

<step id="8" status="pending">
**Update tests:**
- `spec/requests/ui_design_spec.rb`: update to assert `landing-hero` is gone, `tool-hub` is present, fiTLoop card links to `workshop_path`, synCLoop card has `aria-disabled`.
- `spec/requests/app_toolbar_spec.rb`: `t("application.name")` assertions now resolve to "moduSLoop" — verify no breakage.
- `spec/i18n/` (if exists) or i18n-related spec: check `application.name` == "moduSLoop".
</step>

<step id="9" status="pending">
**Update `docs/core/SYSTEM_ARCHITECTURE.md`:** Update "Product" description to reflect moduSLoop platform with fiTLoop as a tool. Update brand references from "Fitloop" → "fiTLoop" and "Fitloop DXF" → "fiTLoop DXF nesting tool within moduSLoop".
</step>

<step id="10" status="pending">
**Full regression run:** `bundle exec rspec` — ensure 0 failures.
</step>

</implementation_plan>


```
moduSLoop (plataforma — auth, nav, home, favicon)
  ├── 🟦 fiTLoop   → /taller  (distribución de láminas DXF)  [ACTIVO]
  ├── 🔵 synCLoop  → (deshabilitado — próximamente)           [PLACEHOLDER]
  └── (espacio para herramientas futuras)
```

**Cómo se "casan" los nombres:** moduSLoop es el ecosistema/plataforma; fiTLoop es una de sus herramientas. Dentro del taller, el branding es `fiTLoop` con su logo dorado/azul actual. En el home de moduSLoop, la tarjeta de fiTLoop lleva el logo de fiTLoop como thumbnail dentro de la tarjeta de la plataforma.

---

## Scope de cambios en el código

### 1 — Nueva Home (`/`) — moduSLoop Hub

- **`app/views/home/index.html.erb`**: Rediseño completo. Grid de tarjetas:
  - Tarjeta **fiTLoop** (activa): logo `fitloop-logo.png`, descripción breve, enlace a `/taller`.
  - Tarjeta **synCLoop** (deshabilitada): logo `logo-syncloop.png`, badge "Próximamente", sin enlace.
- **`app/assets/stylesheets/application.css`**: Nuevas clases `.tool-hub`, `.tool-card`, `.tool-card--disabled`, etc. Paleta moduSLoop (azul marino + verde menta del logo).

### 2 — Branding plataforma (moduSLoop)

| Archivo | Cambio |
|---------|--------|
| `app/views/layouts/application.html.erb` | `<link rel="icon">` → `icono-modusloop.png`; `<title>` → "moduSLoop" |
| `config/locales/es.yml` | `application.name: "moduSLoop"` |
| `config/locales/en.yml` | idem |
| `config/locales/es_panic.yml` | idem |
| `app/views/shared/_app_toolbar.html.erb` | Sin cambios funcionales (ya oculta "Mi taller" en home) |

### 3 — Rename "Fitloop/fitloop/FitLoop" → "fiTLoop" (sweep completo)

Todos los archivos donde aparece como nombre de marca (i18n, vistas, comentarios, docs core):
- `config/locales/es.yml`, `en.yml`, `es_panic.yml`
- `app/views/**/*.html.erb` (textos visibles)
- `app/assets/stylesheets/application.css` (comentarios)
- `docs/core/SYSTEM_ARCHITECTURE.md` (texto descriptivo)
- **Excepción:** nombres de clases Ruby (`Nesting::*`, `ProjectReadinessValidator`, etc.) y rutas (`/taller`) no se tocan — son identificadores internos, no nombres de marca.

### 4 — Auth (pantallas Devise)

- El logo en login/registro/recuperación de contraseña: actualmente muestra el logo de fiTLoop (via `minilogo`). Se mantiene fiTLoop logo en las páginas de auth de fiTLoop, pero el `<title>` de la ventana pasa a "moduSLoop".
- **Alternativa:** ¿Mostrar logo de moduSLoop en auth y logo de fiTLoop solo dentro del taller? → **PREGUNTA PENDIENTE — ver abajo.**

---

## ❓ Una última pregunta antes de cerrar el spec

**Sobre el logo en las pantallas de login/registro:** Actualmente el usuario ve el logo de fiTLoop cuando va a iniciar sesión. Como el login es de **toda la plataforma moduSLoop**, ¿qué logo debería aparecer ahí?

- **Opción A:** Logo de **moduSLoop** en login/registro (porque son pantallas de la plataforma, no de fiTLoop).
- **Opción B:** Mantener el logo de **fiTLoop** en login/registro (porque el contexto de entrada al taller sigue siendo fiTLoop).

¿Cuál prefieres?




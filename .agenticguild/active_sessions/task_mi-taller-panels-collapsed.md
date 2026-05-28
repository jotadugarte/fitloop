# Task: Mi taller always collapsed panels (sheet inventory + DXF detail)

**Created:** 2026-05-28  
**Status:** Planning  
**Classification:** Bugfix  
**Owner request:** En `Mi taller`, sin importar la ruta de entrada, los paneles **Inventario de láminas** y **Detalle DXF** deben mostrarse **siempre cerrados** (nunca desplegados por defecto).

---

## Context / suspected cause

- Mi taller contiene secciones tipo acordeón/`details`/paneles colapsables.
- El estado de “open/closed” puede estar quedando:
  - Persistido en el DOM (atributo `open`), o
  - Forzado por JS (Stimulus), o
  - Rehidratado por Turbo/frames, o
  - Derivado de navegación previa (back/forward cache, turbo cache).

---

## Implementation Plan

<implementation_plan>
  <step id="1" status="complete">Write a failing request/system spec asserting both panels are rendered collapsed by default on `/taller`, independent of referrer (at least two entry routes).</step>
  <step id="2" status="complete">Identify the UI component(s) responsible for these panels (ERB partial + Stimulus controller). Determine current source of truth for open/closed state and why it sometimes defaults to open.</step>
  <step id="3" status="complete">Implement deterministic default-collapsed behavior on initial render (server-side markup) and on Turbo navigation (client-side), ensuring no route/referrer can flip the default to open.</step>
  <step id="4" status="pending">Add a regression guard: ensure any persisted UI state does not re-open these panels on revisit (Turbo cache/back). Keep the exception behavior explicit (only open when user actively opens it on-page, not on load).</step>
  <step id="5" status="pending">Run focused specs and confirm the new test passes; ensure no unrelated panel behaviors regress.</step>
</implementation_plan>


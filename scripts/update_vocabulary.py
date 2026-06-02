#!/usr/bin/env python3
"""
Script de actualización de vocabulario: anidado → distribución
Solo modifica texto visible en UI (config/locales/es.yml)
"""

import re

ES_YML = "config/locales/es.yml"

# Lista de reemplazos exactos: (texto_actual, texto_nuevo)
# Se aplican en orden, uno por uno, sobre el contenido completo del archivo.
REPLACEMENTS = [

    # ── 1. workspace ──────────────────────────────────────────────────────────
    (
        'default_title: "Sesión de anidado"',
        'default_title: "Sesión de distribución"',
    ),

    # ── 2. billing.paywall ────────────────────────────────────────────────────
    (
        'intro: "Para descargar el DXF anidado necesitas pagar esta descarga o tener un plan activo."',
        'intro: "Para descargar el DXF final necesitas pagar esta descarga o tener un plan activo."',
    ),
    (
        'meic_sinpe_hint: "Precio especial con SINPE Móvil. El precio con tarjeta aparece como referencia."',
        'meic_sinpe_hint: "Descuento especial con SINPE Móvil."',
    ),
    (
        '        title: "Tu DXF anidado está listo"',
        '        title: "Tu DXF final está listo"',
    ),
    (
        '        lead: "El anidado terminó. Elige cómo desbloquear la descarga:"',
        '        lead: "Elige cómo desbloquear la descarga:"',
    ),

    # ── 3. billing.mis_pagos ──────────────────────────────────────────────────
    (
        'downloads_heading: "Descargas sueltas"',
        'downloads_heading: "Descargas únicas"',
    ),
    (
        'downloads_lead: "DXF anidados que pagaste. Cada uno queda disponible 24 horas desde la confirmación del pago."',
        'downloads_lead: "DXF finalizados que pagaste. Cada uno queda disponible 24 horas desde la confirmación del pago."',
    ),
    (
        'single_purchases: "Descargas sueltas pagadas"',
        'single_purchases: "Descargas únicas pagadas"',
    ),
    (
        'no_single_purchases: "Aún no tienes descargas sueltas pagadas."',
        'no_single_purchases: "Aún no tienes descargas únicas pagadas."',
    ),
    (
        'row_nested_at: "Anidado %{at}"',
        'row_nested_at: "Sesión %{at}"',
    ),
    (
        'payments_lead: "Registro de cobros por descargas sueltas y planes."',
        'payments_lead: "Registro de cobros por descargas únicas y planes."',
    ),
    # purpose.single_download (en mis_pagos, no en cart — distinguir por contexto)
    # Estos dos bloques tienen la misma clave; los reemplazamos juntos después.
    (
        '        lead: "Aquí ves tu plan activo, las descargas sueltas que pagaste y el historial de pagos simulados."',
        '        lead: "Aquí ves tu plan activo, las descargas únicas que pagaste y el historial de pagos simulados."',
    ),

    # ── 4. billing.planes ─────────────────────────────────────────────────────
    (
        'success: "Plan activado. Ya puedes descargar el DXF anidado desde tu proyecto."',
        'success: "Plan activado. Ya puedes descargar el DXF final desde tu proyecto."',
    ),

    # ── 5. billing.checkout.pending_lock ─────────────────────────────────────
    (
        'duplicate_checkout_blocked: "Ya tenés un pago SINPE en curso para este anidado. Revisá Mis pagos o esperá a que termine el bloqueo del taller."',
        'duplicate_checkout_blocked: "Ya tenés un pago SINPE en curso para esta distribución. Revisá Mis pagos o esperá a que termine el bloqueo del taller."',
    ),
    (
        'lock_expired_message: "Podés volver a anidar o cambiar láminas. Si ya pagaste, la descarga aparecerá en Mis pagos cuando ONVO confirme el cobro."',
        'lock_expired_message: "Podés volver a distribuir o cambiar láminas. Si ya pagaste, la descarga aparecerá en Mis pagos cuando ONVO confirme el cobro."',
    ),
    (
        'released: "Intento de pago cancelado. Podés volver a anidar o cambiar láminas."',
        'released: "Intento de pago cancelado. Podés volver a distribuir o cambiar láminas."',
    ),

    # ── 6. billing.checkout.pending_workshop_lock ────────────────────────────
    (
        'message: "No cambies láminas ni vuelvas a anidar hasta que termine; si lo hacés, podés perder la descarga de este resultado."',
        'message: "No cambies láminas ni vuelvas a distribuir hasta que termine; si lo hacés, podés perder la descarga de este resultado."',
    ),

    # ── 7. billing.checkout.onvo — SINPE ─────────────────────────────────────
    (
        '        sinpe_how_step_2: "Pulsa «Procesar pago»; te mostraremos el monto exacto y el número SINPE destino de ONVO."',
        '        sinpe_how_step_2_html: "Pulsa «Procesar pago»; te mostraremos el <strong class=\\"sinpe-amount-emphasis\\">monto exacto</strong> y el número SINPE destino de ONVO."',
    ),
    (
        '        sinpe_how_step_3: "Transferí ese monto desde tu cuenta (debe coincidir la identificación indicada)."',
        '        sinpe_how_step_3_html: "Transferí ese <strong class=\\"sinpe-amount-emphasis\\">monto exacto</strong> desde tu cuenta (debe coincidir la identificación indicada)."',
    ),
    (
        'sinpe_fields_title: "Datos del transferente (SINPE Móvil)"',
        'sinpe_fields_title: "Datos (SINPE Móvil)"',
    ),

    # ── 8. billing.checkout ───────────────────────────────────────────────────
    (
        '      single_download: "Descarga suelta"',
        '      single_download: "Descarga única"',
    ),
    (
        'plan_quota_prioritized: "Tienes cupo mensual en tu plan activo. Descarga desde el proyecto sin pagar esta descarga suelta."',
        'plan_quota_prioritized: "Tienes cupo mensual en tu plan activo. Descarga desde el proyecto sin pagar esta descarga única."',
    ),
    # purpose.single_download en mis_pagos
    (
        '        single_download: "Descarga suelta"',
        '        single_download: "Descarga única"',
    ),

    # ── 9. home ───────────────────────────────────────────────────────────────
    (
        '      tagline: "Anidado de láminas DXF"',
        '      tagline: "Distribución de láminas para corte"',
    ),
    (
        '      subtitle: "Optimización de cortes para arquitectura"',
        '      subtitle: "Optimización de cortes para modelos, maquetas y proyectos manuales"',
    ),

    # ── 10. projects ──────────────────────────────────────────────────────────
    (
        'nesting_parameters_updated: "Parámetros de anidado actualizados."',
        'nesting_parameters_updated: "Parámetros de distribución actualizados."',
    ),
    # setup.welcome.intro
    (
        '        intro: "FitLoop coloca tus piezas de corte (archivos DXF) sobre las láminas que indiques, respetando márgenes y separación, para aprovechar mejor el material."\r\n        steps_title: "En esta pantalla"\r\n        steps:\r\n          - "Añade tus láminas: ancho, alto y cuántas tienes de cada tamaño. Si dejas la cantidad en blanco, ese tipo de lámina será ilimitado."\r\n          - "Ajusta la separación entre piezas y el margen del borde en «Parámetros de anidado»."\r\n          - "Sube tus DXF y elige la capa de corte (principal) y las auxiliares (grabado, marcas…)."\r\n          - "Pulsa «Iniciar anidado» para ver el resultado."',
        '        intro: "FitLoop organiza tus piezas de corte (archivos DXF) dentro de las láminas que indiques, respetando márgenes y separación, para aprovechar mejor el material."\r\n        steps_title: "En esta pantalla"\r\n        steps:\r\n          - "Inventario de láminas: añade tamaños y cantidades; reordena la prioridad de uso arrastrando filas. Si dejas la cantidad en blanco, ese tipo de lámina será ilimitado."\r\n          - "Ajusta la separación entre piezas y el margen del borde en «Parámetros de distribución»."\r\n          - "Sube tus DXF y elige la capa de corte (principal) y las auxiliares (grabado, marcado…)."\r\n          - "Pulsa «Iniciar distribución» para ver el resultado."',
    ),
    # show.session_title
    (
        '      session_title: "Tu anidado"',
        '      session_title: "Tu distribución"',
    ),
    # show.welcome (bloque completo)
    (
        '        intro: "FitLoop coloca tus piezas de corte (archivos DXF) sobre las láminas que indiques, respetando márgenes y separación, para aprovechar mejor el material."\r\n        steps_title: "En esta pantalla"\r\n        steps:\r\n          - "Inventario de láminas: añade tamaños y cantidades; reordena la prioridad de uso arrastrando filas."\r\n          - "Detalle DXF: sube archivos y elige la capa principal de corte y las auxiliares (grabado, marcas…)."\r\n          - "Vistas previas y piezas no colocadas: tras anidar, revisa cómo quedaron las piezas en cada lámina y cuáles no entraron en las láminas disponibles."\r\n          - "Acciones de anidado: inicia el anidado, vuelve a anidar o cancela el proceso según el estado del proyecto."\r\n          - "Parámetros de anidado: ajusta la separación entre piezas y el margen del borde de la lámina cuando lo necesites."',
        '        intro: "FitLoop organiza tus piezas de corte (archivos DXF) dentro de las láminas que indiques, respetando márgenes y separación, para aprovechar mejor el material."\r\n        steps_title: "En esta pantalla"\r\n        steps:\r\n          - "Inventario de láminas: añade tamaños y cantidades; reordena la prioridad de uso arrastrando filas. Si dejas la cantidad en blanco, ese tipo de lámina será ilimitado."\r\n          - "Detalle DXF: sube archivos y elige la capa principal de corte y las auxiliares (grabado, marcado…)."\r\n          - "Vistas previas y piezas no colocadas: luego de la distribución, revisa cómo quedaron las piezas en cada lámina y cuáles no entraron en las láminas disponibles. Divide automáticamente con Fitloop o descarta la pieza."\r\n          - "Acciones de distribución: inicia la distribución, vuelve a distribuir o cancela el proceso según el estado del proyecto."\r\n          - "Parámetros de distribución: ajusta la separación entre piezas y el margen del borde de la lámina cuando lo necesites."',
    ),
    # show.nesting_parameters_title
    (
        '      nesting_parameters_title: "Parámetros de anidado"',
        '      nesting_parameters_title: "Parámetros de distribución"',
    ),
    # show.download_nested_dxf
    (
        '      download_nested_dxf: "Descargar DXF anidado"',
        '      download_nested_dxf: "Descargar DXF final"',
    ),
    # show.nested_dxf_unavailable
    (
        '      nested_dxf_unavailable: "No hay un anidado listo para descargar. Vuelve a anidar o revisa el estado del proyecto."',
        '      nested_dxf_unavailable: "No hay un DXF final listo para descargar. Vuelve a distribuir o revisa el estado del proyecto."',
    ),
    # show.actions_title
    (
        '      actions_title: "Acciones de anidado"',
        '      actions_title: "Acciones de distribución"',
    ),
    # history.title
    (
        '      title: "Historial de anidados"',
        '      title: "Historial de distribuciones"',
    ),
    # source_preview.empty
    (
        '      empty: "Selecciona capas para anidar y sube un DXF para ver el archivo original aquí."',
        '      empty: "Selecciona capas para distribuir y sube un DXF para ver el archivo original aquí."',
    ),
    # preview.title
    (
        '      title: "Vista previa del anidado"',
        '      title: "Vista previa de la distribución"',
    ),
    # preview.empty
    (
        '      empty: "Aún no hay vista previa. Ejecuta un anidado para ver las colocaciones aquí."',
        '      empty: "Aún no hay vista previa. Ejecuta una distribución para ver las colocaciones aquí."',
    ),
    # form.consumption_order_legend
    (
        '      consumption_order_legend: "El motor de anidado consume los tipos de lámina según su prioridad."',
        '      consumption_order_legend: "El motor de distribución consume los tipos de lámina según su prioridad."',
    ),
    # form.nesting_settings_legend
    (
        '      nesting_settings_legend: "Parámetros de anidado"',
        '      nesting_settings_legend: "Parámetros de distribución"',
    ),

    # ── 11. nesting ───────────────────────────────────────────────────────────
    (
        '    start: "Iniciar anidado"',
        '    start: "Iniciar distribución"',
    ),
    (
        '    started: "Trabajo de anidado iniciado."',
        '    started: "Trabajo de distribución iniciado."',
    ),
    (
        '    cancelled: "Anidado cancelado."',
        '    cancelled: "Distribución cancelada."',
    ),
    (
        '    running: "Ejecutando motor de anidado…"',
        '    running: "Ejecutando motor de distribución…"',
    ),
    (
        '      queued: "En cola para anidar…"',
        '      queued: "En cola para distribuir…"',
    ),
    (
        '      preparing: "Preparando el trabajo de anidado…"',
        '      preparing: "Preparando el trabajo de distribución…"',
    ),
    (
        '      starting: "Iniciando el motor de anidado…"',
        '      starting: "Iniciando el motor de distribución…"',
    ),
    (
        '      writing_outputs: "Generando archivos anidados…"',
        '      writing_outputs: "Generando archivos de distribución…"',
    ),
    (
        '    completed: "Anidado completado."',
        '    completed: "Distribución completada."',
    ),
    (
        '    partial: "Anidado terminado con huérfanos."',
        '    partial: "Distribución terminada con huérfanos."',
    ),
    (
        '    failed: "Anidado fallido."',
        '    failed: "Distribución fallida."',
    ),
    (
        '    progress_heading: "Progreso del anidado"',
        '    progress_heading: "Progreso de la distribución"',
    ),
    (
        '    renest: "Volver a anidar"',
        '    renest: "Volver a distribuir"',
    ),
    (
        '    renest_started: "Reanidado iniciado. Las ejecuciones anteriores se conservan en el historial."',
        '    renest_started: "Nueva distribución iniciada. Las ejecuciones anteriores se conservan en el historial."',
    ),
    (
        '    nest_updated_pieces: "Anidar con piezas actualizadas"',
        '    nest_updated_pieces: "Distribuir con piezas actualizadas"',
    ),
    (
        '    nest_updated_pieces_started: "Anidado iniciado con las piezas actualizadas de las divisiones aceptadas."',
        '    nest_updated_pieces_started: "Distribución iniciada con las piezas actualizadas de las divisiones aceptadas."',
    ),
    (
        '    nest_updated_pieces_unavailable: "Aún no hay piezas derivadas de divisiones aceptadas para anidar."',
        '    nest_updated_pieces_unavailable: "Aún no hay piezas derivadas de divisiones aceptadas para distribuir."',
    ),
    (
        '      no_sheet_capacity: "Añade más láminas al inventario o vuelve a anidar."',
        '      no_sheet_capacity: "Añade más láminas al inventario o vuelve a distribuir."',
    ),
    (
        '      unknown: "Revisa el DXF y el inventario de láminas, luego vuelve a anidar."',
        '      unknown: "Revisa el DXF y el inventario de láminas, luego vuelve a distribuir."',
    ),
    (
        '      accepted: "División aceptada — listo para re-anidar con piezas actualizadas."',
        '      accepted: "División aceptada — listo para re-distribuir con piezas actualizadas."',
    ),
    (
        '      accepted_pending_nest: "División aceptada. Las piezas hijas están listas; usa «Anidar con piezas actualizadas» en Acciones."',
        '      accepted_pending_nest: "División aceptada. Las piezas hijas están listas; usa «Distribuir con piezas actualizadas» en Acciones de Distribución."',
    ),
    (
        '        step_2: "Sube el archivo actualizado en Detalle DXF (más arriba) y vuelve a ejecutar el anidado."',
        '        step_2: "Sube el archivo actualizado en Detalle DXF (más arriba) y vuelve a ejecutar la distribución."',
    ),
    (
        '        orphan_geometry_missing: "Falta la geometría del huérfano — ejecuta un anidado antes de confirmar."',
        '        orphan_geometry_missing: "Falta la geometría del huérfano — ejecuta una distribución antes de confirmar."',
    ),

    # ── 12. project_readiness ─────────────────────────────────────────────────
    (
        '    heading: "Aún no se puede iniciar el anidado"',
        '    heading: "Aún no se puede iniciar la distribución"',
    ),
    (
        '    no_layers_selected: "Selecciona al menos una capa para incluir en el anidado."',
        '    no_layers_selected: "Selecciona al menos una capa para incluir en la distribución."',
    ),

    # ── 13. project_layers ────────────────────────────────────────────────────
    (
        '    section_note: "Elige la capa principal para el contorno a anidar. Grabado, marcas, texto y otras capas auxiliares se desplazan con la pieza que las contiene."',
        '    section_note: "Elige la capa principal para las piezas de corte a distribuir. Grabado, marcas, texto y otras capas auxiliares se desplazan con la pieza que las contiene."',
    ),
    (
        '      tooltip: "Contornos a anidar; el resto queda dentro de cada pieza."',
        '      tooltip: "Contornos a distribuir; el resto queda dentro de cada pieza."',
    ),
    (
        '      selection_hint: "La capa principal define el contorno de cada pieza a anidar. Todo lo dibujado en capas auxiliares (grabado, marcas, texto…) se desplaza junto con la pieza que lo contiene."',
        '      selection_hint: "La capa principal define el contorno de cada pieza a distribuir. Todo lo dibujado en capas auxiliares (grabado, marcas, texto…) se desplaza junto con la pieza que lo contiene."',
    ),
    (
        '      legend: "Incluir capas en el anidado"',
        '      legend: "Incluir capas en la distribución"',
    ),
    (
        '      save: "Guardar e iniciar anidado"',
        '      save: "Guardar e iniciar distribución"',
    ),

    # ── 14. admin ─────────────────────────────────────────────────────────────
    (
        '      nest_completed: "Anidado finalizado"',
        '      nest_completed: "Distribución finalizada"',
    ),
    (
        '        nest_completed_sub: "Eventos de anidado (<code>nest_completed</code>) registrados"',
        '        nest_completed_sub: "Eventos de distribución (<code>nest_completed</code>) registrados"',
    ),
]


def apply_replacements(content, replacements):
    for old, new in replacements:
        count = content.count(old)
        if count == 0:
            print(f"  ⚠️  NO ENCONTRADO: {repr(old[:60])}...")
        elif count > 1:
            print(f"  ⚠️  MÚLTIPLES ({count}x): {repr(old[:60])}...")
        else:
            content = content.replace(old, new)
            print(f"  ✓  {repr(old[:60])}...")
    return content


def main():
    with open(ES_YML, "r", encoding="utf-8") as f:
        original = f.read()

    print(f"Procesando {ES_YML} ({len(original)} bytes)...")
    updated = apply_replacements(original, REPLACEMENTS)

    if updated == original:
        print("\n❌ No se realizó ningún cambio.")
        return

    with open(ES_YML, "w", encoding="utf-8") as f:
        f.write(updated)

    changed = sum(1 for (o, n) in REPLACEMENTS if o in original and o != n)
    print(f"\n✅ Listo. {changed} reemplazos aplicados.")


if __name__ == "__main__":
    main()

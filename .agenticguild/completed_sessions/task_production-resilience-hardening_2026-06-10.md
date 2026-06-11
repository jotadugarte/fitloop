# Active Session: Production Resilience Hardening

<metadata>
  <task_name>production-resilience-hardening</task_name>
  <type>Chore / Ops</type>
  <branch>feat/production-resilience-hardening</branch>
  <status>Implementación completada con éxito</status>
</metadata>

## Contexto

Tres ítems pendientes del ROADMAP (§4 y §5) que no tocan código Rails. Son configuraciones de infraestructura pura para proteger la **durabilidad y continuidad del servicio** en producción (`modusloop.com` en `server-zelda`).

| Ítem | Categoría |
|------|-----------|
| SSL/TLS Full (strict) en Cloudflare | Seguridad de canal |
| Respaldos de base de datos + storage | Recuperación ante desastre |
| Cron semanal `docker system prune` | Prevención de disco lleno |

---

## Arquitectura relevante (de ADR-0007 + DEPLOY.md)

- **Host:** Linux VM (`server-zelda`), gestionado por **Coolify + Docker**
- **Acceso público:** Cloudflare Tunnel (`cloudflared`) — sin Nginx/Caddy; el túnel cifra el canal end-to-end por diseño
- **Bases de datos (4):** `fitloop_production`, `_cache`, `_queue`, `_cable` — PostgreSQL en contenedor Coolify
- **Volúmenes Docker confirmados en `server-zelda`:**
  | Volumen | Uso |
  |---------|-----|
  | `fitloop-prod-storage` | ✅ Active Storage producción — **respaldar** |
  | `fitloop-dev-storage` | Active Storage desarrollo — no respaldar |
  | `postgres-data-lwwmi2q3se8k3cj84zkzeg52` | PostgreSQL instancia (prod o dev) — Coolify gestiona backup |
  | `postgres-data-ugys5yyx95h9dmaypy6cr5j7` | PostgreSQL instancia (prod o dev) — Coolify gestiona backup |
  | `coolify-db` / `coolify-redis` | Internos de Coolify — no respaldar |
- **Active Storage backend:** `Disk` local (ver `config/storage.yml`) — NO es S3 aún
- **Acceso SSH al host:** confirmado
- **Tamaño de `fitloop-prod-storage`:** pendiente confirmar (esperando `du -sh`)

---

## ✅ Decisiones Tomadas

### D1 — SSL/TLS: ✅ CERRADO
**Acción ejecutada:** Cloudflare Dashboard estaba en `Full` → cambiado a `Full (strict)`. Canal end-to-end encriptado confirmado. No se requiere certificado de origen adicional por usar Cloudflare Tunnel.

### D2 — Proveedor de backup: Cloudflare R2
**Decisión:** Usar **Cloudflare R2** como destino de todos los backups.
- Razón: ya usan Cloudflare; **10 GB gratis**; **egress gratuito** (a diferencia de S3/B2).
- Bucket a crear: `modusloop-backups`
- Estructura interna del bucket:
  ```
  modusloop-backups/
    db/YYYY-MM-DD/fitloop_production.dump
    storage/YYYY-MM-DD/storage.tar.gz
  ```

### D3 — Qué respaldar
| Recurso | Respaldar | Razón |
|---------|-----------|-------|
| `fitloop_production` DB | ✅ SÍ | Datos de usuarios, pagos, proyectos |
| `fitloop_production_cache` | ❌ NO | Se regenera sola |
| `fitloop_production_queue` | ❌ NO | Jobs efímeros |
| `fitloop_production_cable` | ❌ NO | WebSocket state efímero |
| `storage/` (Active Storage) | ✅ SÍ | DXFs subidos + nested DXF del producto |

### D4 — Retención: 30 días rolling
**Decisión:** Backup **diario**, retención **30 días rolling** (el día 31 borra el más viejo). Estándar de facto para SaaS pequeño. Seguro para detectar errores que se notan tarde o corrupción gradual. Costo prácticamente cero en R2 para este volumen.

### D5 — Mecanismo de backup
| Recurso | Herramienta | Cómo |
|---------|-------------|------|
| DB `fitloop_production` | **Coolify built-in** backup de PostgreSQL → R2 S3-compatible | Panel Coolify → Database → Backups → configurar destino S3 con credenciales R2 |
| `storage/` (archivos) | **`rclone`** en host via cron | `rclone sync /ruta/storage r2:modusloop-backups/storage/$(date +%F)/` |

**Cómo encontrar la ruta del storage en el host** (correr en `server-zelda` vía SSH):
```bash
du -sh $(docker volume inspect fitloop-storage --format '{{.Mountpoint}}')
```
Esto muestra el tamaño real del volumen y su ruta absoluta en el host para configurar `rclone`.

### D6 — Docker disk purge: cron en host
**Decisión:** Cron en host (`server-zelda`) via `crontab -e`. Más confiable que Coolify porque opera directamente sobre el daemon Docker del host.
- **Setup:** Una sola vez — SSH al servidor → `crontab -e` → agregar línea → guardar. Luego corre automáticamente cada semana sin intervención.
- **Frecuencia:** Domingos a las 03:00 AM (hora local del servidor)
- **Comando:** `docker system prune -f` (solo elimina recursos SIN usar — contenedores protegidos automáticamente)
- **Tamaño de `fitloop-prod-storage`:** **52 KB** — tier gratuito R2 (10 GB) cubre holgadamente
- **Ruta absoluta en host:** `/var/lib/docker/volumes/fitloop-prod-storage/_data`

---

## Verificación esperada

| Ítem | Smoke test |
|------|-----------| 
| SSL Full strict | ✅ Ya hecho — Cloudflare Dashboard en `Full (strict)` |
| DB backup | Primer dump visible en R2 `modusloop-backups/db/YYYY-MM-DD/` al día siguiente |
| Storage backup | `rclone ls r2:modusloop-backups/storage/$(date +%F)/` muestra archivos |
| Docker prune | `docker system df` muestra reducción de espacio el lunes siguiente al primer domingo |

---

<implementation_plan>
  <type>Chore/Ops</type>
  <summary>
    Configuración de infraestructura de resiliencia en producción para modusloop.com.
    No hay cambios de código Rails. Todos los pasos son operaciones en paneles y CLI del servidor.
    SSL/TLS ya completado. Quedan backups externos (R2) y cron de limpieza Docker.
  </summary>

  <step id="1" status="complete" category="ops">
    Marcar SSL/TLS como completado en ROADMAP.md.
    Mover el ítem "Certificado SSL/TLS" de Pending a Done con fecha 2026-06-10 y nota:
    "Cloudflare Dashboard cambiado de Full a Full (strict). Cloudflare Tunnel garantiza cifrado end-to-end sin certificado de origen adicional."
  </step>

  <step id="2" status="complete" category="ops">
    Crear bucket en Cloudflare R2:
    - Ir a dash.cloudflare.com → R2 → Create bucket
    - Nombre: modusloop-backups
    - Región: automática
    - Crear token de API R2 con permisos: Object Read y Object Write sobre ese bucket
    - Anotar: Account ID, Access Key ID, Secret Access Key
  </step>

  <step id="3" status="complete" category="ops">
    Configurar backup de base de datos en Coolify:
    - Panel Coolify → seleccionar la instancia PostgreSQL de producción
    - Sección Backups → Add S3 Destination
    - Endpoint: https://<ACCOUNT_ID>.r2.cloudflarestorage.com
    - Bucket: modusloop-backups
    - Path prefix: db/
    - Access Key ID y Secret Access Key del paso 2
    - Frecuencia: diaria
    - Retención: 30 días
    - Guardar y forzar un primer backup manual para verificar conectividad
  </step>

  <step id="4" status="complete" category="ops">
    Instalar y configurar rclone en host server-zelda (via SSH):
    - curl https://rclone.org/install.sh | sudo bash
    - rclone config → new remote → nombre: r2 → tipo: s3 → provider: Cloudflare
    - Ingresar Access Key ID, Secret Access Key, endpoint del paso 2
    - Verificar: rclone ls r2:modusloop-backups
  </step>

  <step id="5" status="complete" category="ops">
    Crear script de backup de storage en host:
    - Archivo: /usr/local/bin/fitloop-storage-backup.sh
    - Contenido:
        #!/bin/bash
        set -euo pipefail
        DATE=$(date +%F)
        STORAGE=/var/lib/docker/volumes/fitloop-prod-storage/_data
        rclone sync "$STORAGE" "r2:modusloop-backups/storage/$DATE/" --log-file /var/log/fitloop-backup.log
    - chmod +x /usr/local/bin/fitloop-storage-backup.sh
    - Probar manualmente: sudo /usr/local/bin/fitloop-storage-backup.sh
    - Verificar en R2: rclone ls r2:modusloop-backups/storage/
  </step>

  <step id="6" status="complete" category="ops">
    Agregar cron jobs en host (crontab -e como root o con sudo):
    - Backup storage diario a las 02:00 AM:
        0 2 * * * /usr/local/bin/fitloop-storage-backup.sh
    - Docker prune semanal domingos a las 03:00 AM:
        0 3 * * 0 docker system prune -f >> /var/log/docker-prune.log 2>&1
    - Verificar con: sudo crontab -l
  </step>

  <step id="7" status="complete" category="ops">
    Limpiar backups locales de Coolify (si los hay):
    - Verificar que Coolify no esté guardando dumps localmente además de R2
    - Si hay dumps en disco local, confirmar que R2 tiene el mismo contenido y eliminar los locales para liberar espacio
  </step>

  <step id="8" status="complete" category="ops">
    Actualizar ROADMAP.md:
    - Mover "Respaldos de base de datos" de Pending a Done con fecha y descripción del setup
    - Mover "Limpieza automática de Docker" de Pending a Done con fecha y descripción del cron
    - Actualizar también DEPLOY.md sección 10.3: marcar cron semanal como completado
  </step>
</implementation_plan>

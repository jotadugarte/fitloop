# Fitloop — deployment notes (v1)

**Requirement:** [REQ-FIT-QA-001](core/SPEC.md)  
**Deploy strategy:** [ADR-0007](core/ADRs/0007-production-vm-deploy.md) — **Coolify Docker Deployment** (extended container including Rails 8, Thruster, and Python nesting engine). 

## Target topology

Single host (VM) running Coolify with:

| Component | Role |
|-----------|------|
| **Rails 8 Container** | HTTP (via Thruster on port 80), Active Storage, Solid Queue worker |
| **PostgreSQL Database** | Primary database (managed by Coolify or external) |
| **Python 3 venv** (built inside container) | `nesting_engine` CLI invoked from `NestingJob` |

Both Rails and the Python nesting engine run within the same container, sharing the container's filesystem so Active Storage blobs and temp work dirs are visible to both.

## Native nesting dependencies (Dockerized)

Production nesting uses **`python-libnest2d`** (imports `pynest2d`) per [ADR-0001](core/ADRs/0001-nesting-library.md). 

The application [Dockerfile](file:///home/jader/proyectos/fitloop/Dockerfile) handles all package installations:
- Python 3 environment setup.
- Compilation libraries (`cmake`, `libboost-dev`, `build-essential`) in the build stage.
- Prebuilt or built-from-source installation of all pip packages in `requirements.txt` inside the container's virtual environment `/rails/.venv`.

### Smoke check inside the container

You can run the following to verify the environment inside the running Docker container:

```bash
docker exec -it <container-id> /rails/.venv/bin/python -c "from pynest2d import Box, nest; print('pynest2d OK')"
docker exec -it <container-id> /rails/.venv/bin/python -c "from nesting_engine.nest_libnest2d import capabilities; c = capabilities(); assert c.spike_only is False; print(c.library)"
```

Expected: `pynest2d OK` and the library name containing `libnest2d`.

### Troubleshooting

| Symptom | Check |
|---------|--------|
| `ModuleNotFoundError: pynest2d` | Verify that the Dockerfile successfully completed the `pip install` step in build logs. |
| Container fails to start | Check the Coolify application logs (`docker logs`). Ensure database credentials are correct. |

## Environment

Copy `.env.example` to `.env` and set:

| Variable | Purpose |
|----------|---------|
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` | PostgreSQL connection (see `config/database.yml`) |
| `RAILS_MASTER_KEY` | Decrypt `config/credentials.yml.enc` (Rails secrets) |
| `BILLING_GATEWAY` | `simulate` (default dev) or `onvo` for live ONVO checkout |
| `ONVO_MODE`, `ONVO_SECRET_KEY`, `ONVO_PUBLISHABLE_KEY`, `ONVO_WEBHOOK_SECRET` | ONVO API + webhook verification ([ADR-0006](core/ADRs/0006-onvo-live-billing.md)) |
| `GEOLITE2_COUNTRY_MMDB_PATH` | Optional fallback when `CF-IPCountry` is absent (see [Billing geo](#billing-geo-cloudflare--geolite2)) |
| `MAXMIND_LICENSE_KEY` | One-time download of GeoLite2-Country (build/ops host only; not required at Rails runtime) |

**Do not set** `FITLOOP_BILLING_COUNTRY_OVERRIDE` in production unless you intentionally force a single country for all users (QA only).

`Dxf::Python.executable` prefers `Rails.root.join(".venv/bin/python")`; falls back to `python3` on `PATH`.

### Billing geo (Cloudflare + GeoLite2)

Paywall and checkout choose **CRC + SINPE** only when the visitor’s country is **CR**; everyone else sees **USD + card only** ([REQ-FIT-BILL-001](core/SPEC.md)).

| Priority | Source | Production |
|----------|--------|------------|
| 1 | `FITLOOP_BILLING_COUNTRY_OVERRIDE` | **Must be unset** in production |
| 2 | **`CF-IPCountry`** (Cloudflare) | **Required** — primary signal |
| 3 | GeoLite2 Country MMDB | **Recommended fallback** if any request might bypass Cloudflare |
| 4 | User `time_zone == America/Costa_Rica` | Last resort (logged if used without CF) |
| 5 | `session[:billing_country_code]` | Sticky from a prior resolved visit |

#### Cloudflare (mandatory in production)

1. DNS for the Fitloop hostname must be **proxied** (orange cloud) through Cloudflare.
2. Traffic must reach Rails through Cloudflare so each request includes **`CF-IPCountry`** (ISO country code, e.g. `CR`, `US`).
3. Do not strip that header at your load balancer or PaaS unless you replace it with an equivalent country code.

**Verify after deploy:**

- From Costa Rica (or VPN CR): paywall shows **₡**, SINPE options, `data-billing-currency="crc"` in HTML.
- From outside CR: paywall shows **USD**, no SINPE, `data-billing-currency="usd"`.
- Rails log should **not** repeat `[billing.geo] CF-IPCountry missing` on `/taller/descarga-pago` or `/checkout` (warning is throttled to once per 5 minutes per cache).

#### GeoLite2 fallback (recommended)

If `CF-IPCountry` is missing, Fitloop looks up `request.remote_ip` in a local **GeoLite2-Country** database before falling back to user time zone or USD for billing, and to resolve the country code for internal user event analytics telemetry (`Analytics::ResolveCountry`).

1. Create a free [MaxMind GeoLite2](https://www.maxmind.com/en/geolite2/signup) account and a license key.
2. On the build or release host (or locally once, then ship the file):

   ```bash
   export MAXMIND_LICENSE_KEY='your_license_key'
   bin/rails billing:geo:install_geolite2
   ```

   Default output: `storage/geoip/GeoLite2-Country.mmdb` (gitignored).

3. In production ENV:

   ```bash
   GEOLITE2_COUNTRY_MMDB_PATH=/app/storage/geoip/GeoLite2-Country.mmdb
   ```

4. Refresh the MMDB monthly (MaxMind license). Re-run the install task or automate with `geoipupdate`.

5. Run the checklist task after deploy:

   ```bash
   bin/rails billing:geo:check
   ```

**Production alerts:** when a billing page is hit without `CF-IPCountry` (and no dev override), Rails logs:

`[billing.geo] CF-IPCountry missing on <source>; resolved country=…`

Monitor this in your log aggregator on the production VM. Persistent warnings mean Cloudflare is misconfigured or traffic is hitting the origin directly.

#### Local development

- `bin/dev` defaults to **CR** when geo is unavailable (WSL/localhost).
- To simulate abroad, set in `.env`: `FITLOOP_BILLING_COUNTRY_OVERRIDE=US` and **restart** the server.
- `bin/dev` loads `.env` before applying the CR default so `.env` wins over the script default.

GeoLite2 data © [MaxMind](https://www.maxmind.com).

### ONVO webhooks

ONVO sends webhooks from the public internet. `localhost` is not reachable without HTTPS exposure.

#### Local development (ONVO test mode)

1. Start Rails: `bin/dev` (port 3000).
2. Start a tunnel, e.g. [ngrok](https://ngrok.com/): `ngrok http 3000`.
3. Register the webhook URL in the ONVO **test** dashboard: `https://<your-subdomain>.ngrok-free.app/webhooks/onvo` (path must match `POST /webhooks/onvo`).
4. Set `ONVO_WEBHOOK_SECRET` in `.env` to the secret shown in ONVO; restart Rails after changing ENV.
5. Allow the ngrok host in Rails if needed (`config.hosts` — Fitloop already permits common `*.ngrok-free.dev` patterns in development).

**Caveats:**

- Free ngrok URLs **change** when you restart the tunnel unless you use a reserved domain — update the ONVO dashboard each time.
- Use the ngrok **inspector** at `http://127.0.0.1:4040` to replay or debug webhook payloads during integration.

#### Production (ONVO live)

Per [ADR-0007](core/ADRs/0007-production-vm-deploy.md), register a **stable production URL** on the VM’s public domain (behind Cloudflare):

1. Deploy Fitloop on the Linux VM with HTTPS (reverse proxy → Puma/Thruster).
2. In the ONVO **live** dashboard, set webhook URL to `https://<your-production-domain>/webhooks/onvo`.
3. Set `ONVO_WEBHOOK_SECRET`, `ONVO_MODE=live`, and live API keys in host ENV (not committed).
4. Verify delivery in ONVO dashboard and Rails logs after a test payment.

## First-time setup

```bash
bundle install
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
bin/rails db:create db:prepare
bin/rails db:seed   # if seeds exist
```

`db:prepare` loads the main schema and **Solid Queue** tables (`db/queue_schema.rb`) required for background nesting jobs.

### Development: background nesting jobs

By default, development uses the **`:async`** Active Job adapter (jobs run in a background thread inside `bin/rails server`). No separate worker process is required.

```bash
bin/dev
```

**Expected timing:** a small test DXF (e.g. `sample_piece.dxf`) on a 1000×2000 mm sheet usually finishes in **5–30 seconds**. Large or complex files can take **minutes** (up to the project time limit, default 10 minutes).

**Stuck at 3% “En cola…”** for more than ~10 seconds means the job never started. Restart the server after `bin/rails db:prepare`. Check the Rails log for `Performing NestingJob`.

To test **Solid Queue** locally (like production):

```bash
bin/rails db:prepare
ACTIVE_JOB_QUEUE_ADAPTER=solid_queue SOLID_QUEUE_IN_PUMA=1 bin/dev
```

Or two terminals: `bin/rails server` and `bin/jobs start`.

If you see `relation "solid_queue_processes" does not exist`, run `bin/rails db:schema:load:queue`.

If `bin/dev` says a server is already running, stop the old process (`Ctrl+C` or remove `tmp/pids/server.pid` after stopping Puma) and start again.

## Production VM Go-Live (Coolify + Docker)

Normative checklist for deploying Fitloop on a Linux VPS using **Coolify** and **Docker** ([ADR-0007](core/ADRs/0007-production-vm-deploy.md)).

### 1. Database Provisioning
Through the Coolify panel, provision a **PostgreSQL** database service (or connect to an existing external one).
- Create databases: `fitloop_production`, `fitloop_production_cache`, `fitloop_production_queue`, `fitloop_production_cable`.
- Obtain the connection details (`Host`, `Port`, `Username`, `Password`).

### 2. Application Setup in Coolify
Create two resources in Coolify from your git repository:
1. **Production App:**
   - **Branch:** `main`
   - **Domains:** `http://modusloop.com, http://www.modusloop.com`
   - **Build Pack:** `Dockerfile`
2. **Development App:**
   - **Branch:** `main` (or a staging/dev branch if preferred)
   - **Domains:** `http://dev.modusloop.com`
   - **Build Pack:** `Dockerfile`

### 3. Persistent Volumes (Crucial for Active Storage)
To prevent losing uploaded DXF files and nested output files when container restarts, you must configure a persistent volume mapping:
- Go to the **Storages** tab of the application in Coolify.
- Add a new persistent directory storage:
  - **Volume Name:** `fitloop-storage`
  - **Path inside container:** `/rails/storage`

### 4. Environment Variables
In the **Environment Variables** tab of each app in Coolify, configure the following:

| Variable | Production | Development / Staging |
|----------|------------|-----------------------|
| `RAILS_ENV` | `production` | `production` |
| `RAILS_MASTER_KEY` | *From credentials key* | *From credentials key* |
| `SECRET_KEY_BASE` | *Generate: bin/rails secret* | *Generate: bin/rails secret* |
| `PGHOST` / `PGPORT` | *Postgres host & port* | *Postgres host & port* |
| `PGUSER` / `PGPASSWORD` | *Database credentials* | *Database credentials* |
| `FITLOOP_DATABASE_PASSWORD`| *Database user password*| *Database user password*|
| `SOLID_QUEUE_IN_PUMA` | `1` | `1` |
| `BILLING_GATEWAY` | `onvo` | `simulate` *(or `onvo` for test mode)* |
| `ONVO_MODE` | `live` | `test` |
| `ONVO_SECRET_KEY` | *Live ONVO key* | *Test ONVO key* |
| `ONVO_PUBLISHABLE_KEY` | *Live ONVO key* | *Test ONVO key* |
| `ONVO_WEBHOOK_SECRET` | *Live ONVO webhook secret* | *Test ONVO webhook secret* |
| `APP_HOST` | `modusloop.com` | `dev.modusloop.com` |
| `DISCORD_WEBHOOK_URL` | Webhook canal alertas **prod** | Webhook canal alertas **dev** (recomendado separado) |
| `DISCORD_INVITE_URL` | Invite permanente comunidad | Mismo invite que prod |
| `FEEDBACK_NOTIFY_EMAIL` | `soporte@modusloop.com` | Gmail de prueba o mismo soporte |
| `MAILER_SENDER` | `noreply@modusloop.com` | `noreply@modusloop.com` |
| `SMTP_ADDRESS` | Brevo SMTP host | Brevo SMTP host |
| `SMTP_PORT` | `587` | `587` |
| `SMTP_USER` | Brevo login | Brevo login |
| `SMTP_PASSWORD` | Brevo SMTP key | Brevo SMTP key |
| `HONEYBADGER_API_KEY` | API key Honeybadger | *(omitir en dev)* |

> [!WARNING]
> Do not set `FITLOOP_BILLING_COUNTRY_OVERRIDE` in production. For testing billing on the development site, you can set `FITLOOP_BILLING_COUNTRY_OVERRIDE=US` to simulate transactions from outside Costa Rica.

### 5. Deployment & Migrations
Click **Deploy** in the Coolify panel.
Coolify builds the Docker image and executes `bin/docker-entrypoint` which automatically runs migrations (`bin/rails db:prepare`).

Verify that the databases are successfully migrated and the app status is green.

> [!IMPORTANT]
> Since the databases in Coolify are pre-created (provisioned) before deployment, Rails' `db:prepare` will skip loading the database schemas for **Solid Queue** and **Solid Cable** because the databases already exist. You must run these schema load commands once from the Coolify application console/terminal:
> ```bash
> DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bin/rails db:schema:load:queue
> DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bin/rails db:schema:load:cable
> ```



### 6. Cloudflare Tunnel Configuration
Ensure your Cloudflare Tunnel (`cloudflared`) is running on the host machine and has the following "Published application routes" configured:
- `modusloop.com` -> `http://localhost:80`
- `www.modusloop.com` -> `http://localhost:80`
- `dev.modusloop.com` -> `http://localhost:80`

### 7. Securing the Development Environment
Under Cloudflare Zero Trust:
1. Go to **Access -> Applications** and add a **Self-hosted** application.
2. Domain: `dev.modusloop.com`
3. Add a policy (e.g. `Developers`) with the Action set to **Allow**.
4. Create a rule under the policy with Selector **Emails** containing authorized development emails.
5. **Bypass authentication for webhooks:** Add a second policy with the Action set to **Bypass** (or create a separate application rule for the path `/webhooks/onvo`). Set the rule to:
   - **Path:** `/webhooks/onvo`
   - **Selector:** `Everyone`
   *(This is necessary because ONVO is an external service and needs to send webhook notifications to your application without being blocked by Cloudflare's login page. The endpoint itself is secured via signature verification).*


### 8. ONVO Webhooks
Register the webhook URLs in your ONVO dashboards:
- **Live dashboard:** `https://modusloop.com/webhooks/onvo`
- **Test dashboard:** `https://dev.modusloop.com/webhooks/onvo`

### 9. Post-deployment Smoke Check
1. Access `https://dev.modusloop.com` (log in via Cloudflare Access).
2. Upload a sample DXF and trigger a nesting job.
3. Verify the nesting finishes successfully and returns the download options (verifying Ruby-Python integration).
4. Run:
   ```bash
   docker exec -it <container-id> bin/rails billing:geo:check
   ```
   Ensure GeoIP resolution resolves correctly.

## Automated E2E
To run system tests on the project repository:
```bash
bundle exec rspec spec/system/golden_nesting_e2e_spec.rb
```

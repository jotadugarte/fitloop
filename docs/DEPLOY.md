# Fitloop — deployment notes (v1)

**Requirement:** [REQ-FIT-QA-001](core/SPEC.md)  
**Deploy strategy:** [ADR-0007](core/ADRs/0007-production-vm-deploy.md) — **bare-metal Linux VM** (Rails + PostgreSQL + Python `.venv` on one host). **Not** the v1 path: Northflank, stock `Dockerfile`/Kamal without Python nesting.

## Target topology

Single host (VM or container) running:

| Component | Role |
|-----------|------|
| **Rails 8** (Puma) | HTTP, workspace session access, Active Storage, Solid Queue worker |
| **PostgreSQL** | Primary database |
| **Python 3 venv** (`.venv`) | `nesting_engine` CLI invoked from `NestingJob` |

Rails and Python share the same filesystem so Active Storage blobs and temp work dirs are visible to both.

## Prerequisites

- Ruby 3.x + Bundler (see `Gemfile`)
- PostgreSQL 14+
- Python 3.10+ with `pip install -r requirements.txt` inside `.venv` at repo root

## Native nesting dependencies (libnest2d)

Production nesting uses **`python-libnest2d`** (imports `pynest2d`) per [ADR-0001](core/ADRs/0001-nesting-library.md). On **Linux x86_64**, pip installs a prebuilt wheel — no compiler required for the default path.

### Ubuntu / Debian (apt)

For **pip wheel install** (recommended):

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip
```

If you must **build from source** (no matching wheel), also install:

```bash
sudo apt-get install -y cmake build-essential libboost-dev
```

### Python venv (repo root)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

`requirements.txt` pins `python-libnest2d==0.1.3`.

### Smoke check (host / CI parity)

```bash
.venv/bin/python -c "from pynest2d import Box, nest; print('pynest2d OK')"
.venv/bin/python -c "from nesting_engine.nest_libnest2d import capabilities; c = capabilities(); assert c.spike_only is False; print(c.library)"
.venv/bin/pytest nesting_engine/ -q
```

Expected: `pynest2d OK`, library name containing `libnest2d`, and all `nesting_engine` tests passing.

### Troubleshooting

| Symptom | Check |
|---------|--------|
| `ModuleNotFoundError: pynest2d` | Re-run `pip install -r requirements.txt` inside `.venv` |
| pip builds from source and fails | Install `cmake`, `build-essential`, `libboost-dev`; use Python 3.10–3.12 on x86_64 |
| Nesting works locally but not in CI | Match Python version; run the smoke check and `pytest nesting_engine/` on the host |

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

If `CF-IPCountry` is missing, Fitloop looks up `request.remote_ip` in a local **GeoLite2-Country** database before falling back to user time zone or USD.

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

## Production VM go-live

Normative checklist for a **bare-metal Linux VPS** ([ADR-0007](core/ADRs/0007-production-vm-deploy.md)). Adjust paths and service names for your provider.

### 1. Server provisioning

- Ubuntu 22.04+ or Debian 12+ on **x86_64**
- Open ports: **80/443** (public); PostgreSQL **not** exposed publicly
- Persistent volume for app root, especially `storage/` (Active Storage)

### 2. Install stack on the VM

```bash
# System packages (see Native nesting dependencies)
sudo apt-get update
sudo apt-get install -y postgresql postgresql-contrib \
  ruby-full build-essential libpq-dev libvips42 \
  python3 python3-venv python3-pip git

# App deploy (example: /var/www/fitloop)
git clone <repo> /var/www/fitloop && cd /var/www/fitloop
bundle install --deployment
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

Create PostgreSQL role `fitloop` and databases: `fitloop_production`, `fitloop_production_cache`, `fitloop_production_queue`, `fitloop_production_cable`.

### 3. Environment (host)

| Variable | Notes |
|----------|--------|
| `RAILS_ENV=production` | |
| `RAILS_MASTER_KEY` | From `config/master.key` |
| `SECRET_KEY_BASE` | Generate: `bin/rails secret` |
| `FITLOOP_DATABASE_PASSWORD` | PostgreSQL password for user `fitloop` |
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` | Or per-DB URLs if using managed PG |
| `SOLID_QUEUE_IN_PUMA=1` | Single-process deploy; or run `bin/jobs` separately |
| `PORT=3000` | Behind reverse proxy |
| `BILLING_GATEWAY=onvo` | Live billing |
| `ONVO_MODE=live` | Production ONVO keys |
| `ONVO_*` | See [Environment](#environment) |
| `GEOLITE2_COUNTRY_MMDB_PATH` | Recommended fallback |
| `REDIS_URL` | Optional; `config/cable.yml` uses Redis for Action Cable in production |

**Do not set** `FITLOOP_BILLING_COUNTRY_OVERRIDE` in production.

### 4. Rails production config (before first boot)

Edit `config/environments/production.rb` for the live domain:

- `config.action_mailer.default_url_options = { host: "your-domain.com", protocol: "https" }`
- `config.hosts << "your-domain.com"` (and `www` if used)
- `config.assume_ssl = true` and `config.force_ssl = true` when TLS terminates at Cloudflare/proxy

Configure SMTP in credentials for Devise confirmation emails (required before checkout).

### 5. Build and migrate

```bash
RAILS_ENV=production bin/rails assets:precompile
RAILS_ENV=production bin/rails db:prepare
RAILS_ENV=production bin/rails billing:geo:install_geolite2   # once, if using GeoLite2
RAILS_ENV=production bin/rails billing:geo:check
```

### 6. Reverse proxy + Cloudflare

1. Point DNS **A/AAAA** to the VM; enable Cloudflare **proxied** (orange cloud).
2. Nginx/Caddy example: terminate TLS (or Flexible SSL via Cloudflare) and `proxy_pass` to `127.0.0.1:3000`.
3. Health check: `GET /up` returns 200.

### 7. Process manager (systemd example)

**Web + Solid Queue in Puma** (`SOLID_QUEUE_IN_PUMA=1`):

```ini
# /etc/systemd/system/fitloop-web.service
[Unit]
Description=Fitloop Rails
After=network.target postgresql.service

[Service]
Type=simple
User=fitloop
WorkingDirectory=/var/www/fitloop
EnvironmentFile=/var/www/fitloop/.env.production
ExecStart=/bin/bash -lc 'bundle exec puma -C config/puma.rb'
Restart=always

[Install]
WantedBy=multi-user.target
```

If not using `SOLID_QUEUE_IN_PUMA`, add a second unit running `bin/jobs start`.

### 8. ONVO production webhook

Register `https://your-domain.com/webhooks/onvo` in ONVO live dashboard; match `ONVO_WEBHOOK_SECRET`.

### 9. Smoke tests on the host

```bash
.venv/bin/python -c "from nesting_engine.nest_libnest2d import capabilities; print(capabilities())"
curl -sf https://your-domain.com/up
```

Manual: upload golden DXF → nest completes → checkout (test/live per policy) → webhook → download. See `docs/QA_MANUAL_CHECKLIST.md` (**Production VM go-live**).

## Production checklist (summary)

1. `RAILS_ENV=production` with `SECRET_KEY_BASE` and `RAILS_MASTER_KEY`.
2. **Billing geo:** Cloudflare proxy enabled; `CF-IPCountry` on billing routes; `GEOLITE2_COUNTRY_MMDB_PATH` set; `bin/rails billing:geo:check` passes; **`FITLOOP_BILLING_COUNTRY_OVERRIDE` unset** (see [Billing geo](#billing-geo-cloudflare--geolite2)).
3. `bin/rails assets:precompile`.
4. `bin/rails db:prepare` (primary + Solid Queue/cache/cable schemas).
5. Run **Solid Queue** (`SOLID_QUEUE_IN_PUMA=1` or `bin/jobs`).
6. Confirm nesting from the host shell (see [Native nesting dependencies](#native-nesting-dependencies-libnest2d)).
7. Active Storage: `:local` with persistent `storage/` (or cloud per `config/storage.yml`).
8. ONVO live webhook on production domain ([ONVO webhooks — Production](#production-onvo-live)).
9. Mailer + `config.hosts` + SSL for public domain.

## Process layout (example)

- **Web:** `bundle exec puma -C config/puma.rb` (with `SOLID_QUEUE_IN_PUMA=1` optional)
- **Jobs (if separate):** `bin/jobs start` or `bundle exec rake solid_queue:start`

## Docker / Kamal (not v1 production path)

The repo includes a `Dockerfile` (Rails + Thruster only, **no Python nesting**). It is **not** used for v1 go-live per [ADR-0007](core/ADRs/0007-production-vm-deploy.md). A future container deploy must add Python `.venv` + `nesting_engine` on a shared filesystem with Active Storage.

## Automated E2E

Golden DXF system spec: `spec/system/golden_nesting_e2e_spec.rb`  
Fixture: `spec/fixtures/golden/sample_piece.dxf`

Run with PostgreSQL available:

```bash
bundle exec rspec spec/system/golden_nesting_e2e_spec.rb
```

# Fitloop — deployment notes (v1)

**Requirement:** [REQ-FIT-QA-001](core/SPEC.md)

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

`Dxf::Python.executable` prefers `Rails.root.join(".venv/bin/python")`; falls back to `python3` on `PATH`.

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

## Production checklist

1. `RAILS_ENV=production` with `SECRET_KEY_BASE` and `RAILS_MASTER_KEY`.
2. `bin/rails assets:precompile` (if using the asset pipeline).
3. `bin/rails db:migrate` on the production database.
4. Run **Solid Queue** alongside the web process (`bin/jobs` or your process manager).
5. Confirm nesting from the host shell (see [Native nesting dependencies](#native-nesting-dependencies-libnest2d)):

   ```bash
   .venv/bin/python -c "from nesting_engine.nest_libnest2d import capabilities; print(capabilities())"
   .venv/bin/python nesting_engine/nest.py 2>&1 | head -1   # usage: nest.py CONFIG_JSON_PATH
   ```

6. Active Storage: configure `config/storage.yml` for disk or cloud per environment.

## Process layout (example)

- **Web:** `bundle exec puma -C config/puma.rb`
- **Jobs:** `bundle exec rake solid_queue:start` (or equivalent for your Rails 8 setup)

## Automated E2E

Golden DXF system spec: `spec/system/golden_nesting_e2e_spec.rb`  
Fixture: `spec/fixtures/golden/sample_piece.dxf`

Run with PostgreSQL available:

```bash
bundle exec rspec spec/system/golden_nesting_e2e_spec.rb
```

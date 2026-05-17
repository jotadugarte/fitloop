# Fitloop — deployment notes (v1)

**Requirement:** [REQ-FIT-QA-001](core/SPEC.md)

## Target topology

Single host (VM or container) running:

| Component | Role |
|-----------|------|
| **Rails 8** (Puma) | HTTP, PIN gate, Active Storage, Solid Queue worker |
| **PostgreSQL** | Primary database |
| **Python 3 venv** (`.venv`) | `nesting_engine` CLI invoked from `NestingJob` |

Rails and Python share the same filesystem so Active Storage blobs and temp work dirs are visible to both.

## Prerequisites

- Ruby 3.x + Bundler (see `Gemfile`)
- PostgreSQL 14+
- Python 3.10+ with `pip install -r requirements.txt` inside `.venv` at repo root

## Environment

Copy `.env.example` to `.env` and set:

| Variable | Purpose |
|----------|---------|
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` | PostgreSQL connection (see `config/database.yml`) |
| `RAILS_MASTER_KEY` | Decrypt `config/credentials.yml.enc` (admin master PIN, secrets) |

`Dxf::Python.executable` prefers `Rails.root.join(".venv/bin/python")`; falls back to `python3` on `PATH`.

## First-time setup

```bash
bundle install
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
bin/rails db:create db:migrate
bin/rails db:seed   # if seeds exist
```

## Production checklist

1. `RAILS_ENV=production` with `SECRET_KEY_BASE` and `RAILS_MASTER_KEY`.
2. `bin/rails assets:precompile` (if using the asset pipeline).
3. `bin/rails db:migrate` on the production database.
4. Run **Solid Queue** alongside the web process (`bin/jobs` or your process manager).
5. Confirm nesting from the host shell:

   ```bash
   .venv/bin/python nesting_engine/nest_bin.py --help
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

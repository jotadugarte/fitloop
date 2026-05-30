# Testing Strategy Matrix — Fitloop

**Purpose:** Defines testing requirements and coverage rules. No feature may be merged without fulfilling these contracts.

**Traceability source:** `docs/core/SPEC.md` (`REQ-FIT-*`).

---

## 1. Traceability Requirement

- **The [REQ-ID] rule:** Every `it(...)` / `describe` block in RSpec and every test function docstring/comment in pytest MUST reference the `REQ-FIT-*` ID it verifies.
- Untraced tests are invalid for merge.
- Controllers/services/models SHOULD include a comment tag matching their primary REQ (e.g. `# [REQ-FIT-DOM-001]`).

---

## 2. Testing Pyramid (this repo)

| Layer | Framework | Location | Rule of engagement | Target |
|-------|-----------|----------|-------------------|--------|
| **Python engine** | pytest | `nesting_engine/tests/` | Unit/integration on extract, nest, CLI outputs; no network; fixture DXFs in `tests/fixtures/` | All engine modules covered |
| **Domain / services** | RSpec | `spec/services/`, `spec/models/` | Mock external I/O; real DB for models | 100% service branches |
| **Jobs** | RSpec | `spec/jobs/` | Mock CLI or use `cli_mock` / real `nest.py` in integration example | Happy + partial + failed paths |
| **HTTP / requests** | RSpec | `spec/requests/` | Status codes, workspace session bind, i18n copy, attachment headers | All routes with business rules |
| **System / E2E** | RSpec + Capybara | `spec/system/` | Golden DXF flow, CRUD, progress UI (`rack_test` driver) | Critical user flows only |
| **Doc / scaffold guards** | Minitest | `test/app/`, `test/architecture/`, `test/spec/` | Verifiers for home, architecture doc, SPEC presence | CI gate on docs |

---

## 3. Commands

```bash
# Rails (from project root)
bundle exec rspec

# Python engine (venv active)
python -m pytest nesting_engine/tests -q

# Fast engine CI (skip real-DXF integration tests)
python -m pytest nesting_engine/tests -q -m "not slow"
```

**CI expectation:** Both suites green before merge (see `bin/ci` if configured). Engine jobs may use `-m "not slow"`; run full suite including `@pytest.mark.slow` before release or when changing DXF fixtures.

---

## 4. REQ-ID → Test Map (representative)

| REQ-ID | Primary specs |
|--------|----------------|
| REQ-FIT-APP-001 | `spec/requests/home_spec.rb`, `test/app/fitloop_home_test.rb` |
| REQ-FIT-ARCH-001 | `test/architecture/system_architecture_doc_test.rb` |
| REQ-FIT-SPEC-001 | `test/spec/spec_doc_test.rb` |
| REQ-FIT-DOM-001 | `spec/models/project*_spec.rb`, `spec/models/sheet_stock_spec.rb` |
| REQ-FIT-AUTH-001 | `spec/services/workspace_spec.rb`, `spec/requests/workspace_access_spec.rb`, `spec/requests/ephemeral_workspace_spec.rb` |
| REQ-FIT-AUTH-002 | `spec/models/user_spec.rb`, `spec/requests/user_registrations_spec.rb`, `spec/requests/user_passwords_spec.rb`, `spec/requests/omniauth_auth_spec.rb`, `spec/requests/account_merge_spec.rb`, `test/spec/auth_billing_spec_doc_test.rb` |
| REQ-FIT-BILL-001 | `test/spec/auth_billing_spec_doc_test.rb`, `spec/models/payment_spec.rb`, `spec/requests/nested_dxf_paywall_spec.rb`, `spec/requests/checkout_simulate_spec.rb`, `spec/requests/checkout_plan_overage_spec.rb`, `spec/requests/checkout_onvo_pay_spec.rb`, `spec/requests/checkout_onvo_ui_spec.rb`, `spec/requests/checkout_onvo_card_spec.rb`, `spec/requests/checkout_onvo_sinpe_spec.rb`, `spec/requests/checkout_payment_status_spec.rb`, `spec/requests/checkout_three_ds_return_spec.rb`, `spec/requests/checkout_duplicate_sinpe_lock_spec.rb`, `spec/requests/checkout_release_pending_lock_spec.rb`, `spec/requests/workshop_pending_payment_lock_spec.rb`, `spec/requests/mis_pagos_show_spec.rb`, `spec/requests/webhooks/onvo_spec.rb`, `spec/services/billing/onvo/*_spec.rb`, `spec/services/billing/checkout_lock_reason_spec.rb`, `spec/services/billing/workshop_lock_window_spec.rb`, `spec/services/billing/pending_checkout_*_spec.rb`, `spec/services/billing/mis_pagos/single_purchase_rows_spec.rb`, `spec/services/billing/pre_retain_nested_dxf_spec.rb`, `spec/services/billing/fulfill_payment_spec.rb`, `spec/services/billing/fail_payment_spec.rb`, `spec/services/billing/gateway_spec.rb`, `spec/services/billing/payment_status_response_spec.rb`, `spec/i18n/billing_auth_locale_spec.rb`; Stimulus helpers `app/javascript/checkout/onvo_checkout_{validation,card_draft,sinpe_transfer}.js` — no JS unit harness; covered via checkout request/UI specs and manual QA (`docs/QA_ONVO_SINPE.md`) |
| REQ-FIT-BILL-002 | `test/spec/auth_billing_spec_doc_test.rb`, `spec/requests/plan_checkout_spec.rb`, `spec/requests/plan_download_hint_spec.rb`, `spec/services/billing/quota_counter_spec.rb`, `spec/i18n/billing_auth_locale_spec.rb` |
| REQ-FIT-BILL-003 | `test/spec/auth_billing_spec_doc_test.rb`, `spec/requests/mis_pagos_download_spec.rb`, `spec/requests/checkout_retention_spec.rb`, `spec/requests/nested_dxf_redownload_spec.rb`, `spec/services/billing/retained_nested_dxf_spec.rb`, `spec/services/billing/download_token_spec.rb`, `spec/jobs/billing/purge_expired_retained_downloads_job_spec.rb`, `spec/i18n/billing_auth_locale_spec.rb` |
| REQ-FIT-UI-001 | `spec/system/projects_spec.rb` |
| REQ-FIT-UI-002 | `spec/requests/project_preview_spec.rb`, `spec/services/nesting/preview_presenter_spec.rb` |
| REQ-FIT-UI-003 | `spec/requests/workspace_access_spec.rb`, `spec/requests/i18n_views_spec.rb` |
| REQ-FIT-UI-004 | `spec/requests/ui_design_spec.rb` |
| REQ-FIT-UI-005 | `spec/requests/locale_spec.rb`, `spec/i18n/locale_key_parity_spec.rb`, `spec/i18n/billing_auth_locale_spec.rb`, `spec/i18n/nesting_phase_labels_spec.rb`, `spec/lib/fitloop_home_verifier_spec.rb` |
| REQ-FIT-DXF-001 | `spec/requests/project_layers_spec.rb` |
| REQ-FIT-DXF-002 | `spec/models/project_layer_spec.rb`, `spec/requests/project_layers_spec.rb`, `spec/services/nesting/config_builder_spec.rb`, `spec/services/dxf/piece_counter_spec.rb`, `spec/requests/project_source_preview_spec.rb`, `spec/system/project_layers_composite_spec.rb`, `test/spec/composite_dxf_spec_doc_test.rb`, `test/architecture/composite_dxf_architecture_doc_test.rb`, `nesting_engine/tests/test_composite_extract.py`, `nesting_engine/tests/test_piece_loader_composite.py`, `nesting_engine/tests/test_decoration_transform.py`, `nesting_engine/tests/test_dxf_output_composite.py`, `nesting_engine/tests/test_nest_pipeline_composite.py`, `nesting_engine/tests/test_dxf_preview_composite.py` |
| REQ-FIT-VAL-001 | `spec/services/project_readiness_validator_spec.rb`, `spec/requests/project_readiness_spec.rb` |
| REQ-FIT-EXT-001 | `nesting_engine/tests/test_extract_contours.py` |
| REQ-FIT-EXT-002 | `nesting_engine/tests/test_extract_insert_blocks.py` |
| REQ-FIT-CLI-001 | `spec/services/nesting/cli_runner_spec.rb`, `spec/jobs/nesting_job_spec.rb` |
| REQ-FIT-NEST-001 | `nesting_engine/tests/test_libnest2d_binding.py`, `nesting_engine/tests/test_nest_libnest2d.py`, `nesting_engine/tests/test_nest_spike.py` |
| REQ-FIT-NEST-002 | `nesting_engine/tests/test_nest_pipeline.py`, `nesting_engine/tests/test_nest_libnest2d.py`, `nesting_engine/tests/test_nest_placement_scoring.py`, `nesting_engine/tests/test_nest_full_sheet_batch.py`, `nesting_engine/tests/test_nest_full_sheet_obstacles.py`, `nesting_engine/tests/test_nest_consolidate_repack.py`, `nesting_engine/tests/test_nest_inter_sheet_search.py`, `nesting_engine/tests/test_nest_intra_sheet_repack.py`, `nesting_engine/tests/test_nest_intra_sheet_peluo_integration.py` (`@pytest.mark.slow`), `nesting_engine/tests/test_nest_multi_bin_epic_integration.py` |
| REQ-FIT-NEST-003 | `spec/services/nesting/status_mapper_spec.rb`, `spec/jobs/nesting_job_integration_spec.rb` |
| REQ-FIT-JOB-001 | `nesting_engine/tests/test_progress_reporter.py`, `test_nest_progress.py`, `test_cli_mock.py`, `spec/services/nesting/job_runner_spec.rb`, `progress_snapshot_spec.rb`, `progress_sync_spec.rb`, `progress_locals_spec.rb`, `cli_runner_spec.rb`, `progress_broadcaster_spec.rb`, `spec/requests/nesting_enqueue_eta_spec.rb`, `project_nesting_sync_spec.rb`, `spec/views/projects/nesting_progress_spec.rb`, `spec/system/nesting_progress_spec.rb`, `spec/i18n/nesting_phase_labels_spec.rb` |
| REQ-FIT-NEST-004 | `spec/requests/nesting_renest_spec.rb`, `spec/jobs/nesting_renest_spec.rb` |
| REQ-FIT-SPLIT-001 | `spec/models/orphan_resolution_spec.rb`, `spec/services/nesting/piece_key_builder_spec.rb`, `spec/services/nesting/orphans_presenter_spec.rb`, `spec/services/nesting/config_builder_split_spec.rb`, `spec/jobs/nesting_split_plan_job_spec.rb`, `spec/requests/orphan_resolutions_spec.rb`, `spec/requests/split_proposals_accept_spec.rb`, `spec/requests/split_proposals_not_feasible_spec.rb`, `spec/requests/nesting_nest_updated_pieces_spec.rb`, `spec/requests/orphan_manual_resolution_spec.rb`, `spec/services/nesting/apply_cancel_split_previews_spec.rb`, `spec/system/orphan_auto_split_spec.rb`, `nesting_engine/tests/test_split_planner.py`, `nesting_engine/tests/test_cli_plan_splits.py`, `nesting_engine/tests/test_piece_loader_split.py`, `test/spec/split_spec_doc_test.rb` |
| REQ-FIT-QA-001 | `spec/system/golden_nesting_e2e_spec.rb` |

---

## 5. Mocking & Stubbing Rules

| Concern | Rule |
|---------|------|
| **External APIs** | No live HTTP in tests |
| **Nesting CLI** | Use `nesting_engine/cli_mock.py` or stub `Nesting::CliRunner.call` unless explicitly integration (`nesting_job_integration_spec`) |
| **Active Storage** | Use `attach` with `StringIO` / fixture files in request specs |
| **Workspace session** | `bind_workspace_session!` / `create_project_for_spec!` (default bind) in request/system specs |
| **Time** | Prefer fixed timestamps in assertions; job timeout tests stub/limit duration where possible |
| **Randomness** | RSpec `randomized with seed` logged; pytest deterministic fixtures |
| **Database** | Default `use_transactional_fixtures = true`; opt out only when necessary (`home_spec`, `locale_spec`, `ui_design_spec` with explicit cleanup) |

---

## 6. System Test Conventions

- Driver: `rack_test` (see `spec/rails_helper.rb`).
- Use `data-testid` attributes — do not rely on CSS classes for assertions.
- Golden DXF: `spec/fixtures/golden/sample_piece.dxf` — do not mutate.
- After UI changes, run `spec/system` before merge.

---

## 7. Adding New Tests

1. Locate REQ-ID in `SPEC.md`.
2. Add smallest layer that proves the behavior (prefer service over system).
3. Name example: `it "[REQ-FIT-XXX-NNN] ..."`.
4. If no REQ exists, update `SPEC.md` first (or open ADR) — do not merge untraced behavior.

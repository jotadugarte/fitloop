<task_session>
  <metadata>
    <task_name>Admin foundation</task_name>
    <type>Feature</type>
    <req_id>REQ-FIT-ADMIN-001 (to be formalised in SPEC.md)</req_id>
    <roadmap_item>Pending #1 — Admin foundation</roadmap_item>
  </metadata>

  ## Decisions log

  | # | Question | Decision |
  |---|----------|----------|
  | 1 | `/admin` skeleton content | Placeholder with links to ventas + analytics |
  | 2 | Admin seeding strategy | Initializer reading `FITLOOP_ADMIN_EMAILS` (CSV). Emails: `jadere@gmail.com`, `massielpgarcia@gmail.com` — stored in `.env` / server ENV, NOT in source code |
  | 3 | `users.admin` column | `boolean NOT NULL DEFAULT false` |
  | 4 | Unauthorized access behavior | 404 for everyone — authenticated non-admin AND unauthenticated (do not leak existence of `/admin`) |
  | 5 | Route | `/admin` (English, internal path, acceptable) |
  | 6 | Test framework | RSpec request specs |

  ## Domain Model

  ### Entity: `User` (extended)
  - **New attribute:** `admin: boolean, NOT NULL, DEFAULT false`
  - **Invariant:** Promoted exclusively via `FITLOOP_ADMIN_EMAILS` ENV on boot; no self-registration flow.
  - **No branded type needed** — plain boolean predicate.

  ### New: `Admin::BaseController`
  - **Responsibility:** Authentication gate + 404 enforcement for all `/admin/*` routes.
  - **Invariants:**
    - Raises `ActionController::RoutingError` for any request where `current_user` is nil OR `current_user.admin?` is false.
    - Does NOT redirect to login (avoids leaking admin endpoint existence).

  <working_notes>
    Session opened 2026-05-31. All 6 decisions locked. Implementation plan written below.
  </working_notes>

  <implementation_plan>
    <classification>Feature — test-first (TDD) required</classification>
    <dependency>Billing domain types (CbC refactor) — DONE</dependency>

    <step id="1" status="complete">
      Write failing RSpec request specs BEFORE any implementation code.

      File: `spec/requests/admin/dashboard_spec.rb`

      Cover:
      - GET /admin as authenticated admin user → 200 OK
      - GET /admin as authenticated non-admin user → 404
      - GET /admin as unauthenticated (no session) → 404

      Run `bundle exec rspec spec/requests/admin/` — all specs must be RED before proceeding.
    </step>

    <step id="2" status="complete">
      Generate and run migration to add `admin` column to `users`:

        bin/rails generate migration AddAdminToUsers admin:boolean

      Edit the generated migration file to enforce NOT NULL and DEFAULT false:

        add_column :users, :admin, :boolean, null: false, default: false

      Run: `bin/rails db:migrate`

      Verify in `db/schema.rb` that `admin` appears with `default: false, null: false`.
    </step>

    <step id="3" status="complete">
      In `app/models/user.rb`, add a traceability comment above the class body:

        # [REQ-FIT-ADMIN-001] admin: boolean column — promoted via FITLOOP_ADMIN_EMAILS initializer.
        # ActiveRecord generates admin? automatically. Never set via user registration flow.

      No new methods required — ActiveRecord generates `admin?` from the boolean column.
    </step>

    <step id="4" status="complete">
      Create `config/initializers/promote_admins.rb`:

        # [REQ-FIT-ADMIN-001] Promote users listed in FITLOOP_ADMIN_EMAILS to admin on boot.
        # Emails are comma-separated. Set in .env (dev) or server ENV (production).
        # Real admin emails must NEVER be committed to source control.
        # Example: FITLOOP_ADMIN_EMAILS=you@example.com,partner@example.com
        Rails.application.config.after_initialize do
          emails = ENV
            .fetch("FITLOOP_ADMIN_EMAILS", "")
            .split(",")
            .map(&:strip)
            .reject(&:blank?)

          if emails.any?
            promoted = User.where(email: emails, admin: false).update_all(admin: true)
            Rails.logger.info "[AdminSeed] Promoted #{promoted} user(s) to admin." if promoted > 0
          end
        rescue => e
          Rails.logger.warn "[AdminSeed] Skipped admin promotion: #{e.message}"
        end

      Also add to `.env.example` (documentation only, no real values):
        FITLOOP_ADMIN_EMAILS=you@example.com,partner@example.com

      Real emails (`jadere@gmail.com`, `massielpgarcia@gmail.com`) go ONLY in:
        - Local `.env` file (gitignored)
        - Production server environment variables
    </step>

    <step id="5" status="complete">
      Create `app/controllers/admin/base_controller.rb`:

        # frozen_string_literal: true

        # [REQ-FIT-ADMIN-001] Base controller for all /admin/* routes.
        # Returns 404 for non-admin and unauthenticated requests — does NOT redirect
        # to login, to avoid leaking the existence of the admin interface.
        module Admin
          class BaseController < ApplicationController
            layout "admin"
            before_action :require_admin!

            private

            def require_admin!
              raise ActionController::RoutingError, "Not Found" unless admin_user?
            end

            def admin_user?
              user_signed_in? && current_user.admin?
            end
          end
        end
    </step>

    <step id="6" status="complete">
      Create `app/controllers/admin/dashboard_controller.rb`:

        # frozen_string_literal: true

        module Admin
          class DashboardController < Admin::BaseController
            def index
            end
          end
        end
    </step>

    <step id="7" status="complete">
      Add to `config/routes.rb` (before the closing `end`):

        namespace :admin do
          root to: "dashboard#index"
        end

      Sub-routes for ventas (`/admin/ventas`) and analytics (`/admin/analytics`) will be
      added in Pending #2 and #3 respectively.
    </step>

    <step id="8" status="complete">
      Create `app/views/layouts/admin.html.erb`.

      Requirements:
      - Minimal layout, separate from public `application` layout.
      - Must NOT include workspace-tab or locale-switcher Stimulus data attributes.
      - Simple top nav: "Fitloop Admin" link to /admin + signed-in admin email + sign-out link.
      - `yield` content area with basic page structure.
      - Reuse existing app CSS via `stylesheet_link_tag "application"`.
    </step>

    <step id="9" status="complete">
      Create `app/views/admin/dashboard/index.html.erb`.

      Content:
      - H1: "Panel de administración"
      - Subtitle: "Bienvenido/a. Selecciona una sección:"
      - Two card/link blocks:
        * "Ventas" → `/admin/ventas` — labelled "Próximamente" (visually disabled)
        * "Analytics" → `/admin/analytics` — labelled "Próximamente" (visually disabled)
      - Use existing app CSS conventions. No Tailwind.
    </step>

    <step id="10" status="complete">
      Run: `bundle exec rspec spec/requests/admin/`

      All specs from Step 1 must now be GREEN. Debug and fix any failures before continuing.
    </step>

    <step id="11" status="complete">
      Run full test suite to verify no regressions:

        bundle exec rspec
        bin/rails test

      All existing specs and tests must remain GREEN.
    </step>

    <step id="12" status="complete">
      Update `docs/ROADMAP.md`:
      - Move item #1 from Pending to Done section with date and session reference.
      - Update status summary table row for Pre-live phase.
    </step>
  </implementation_plan>

</task_session>

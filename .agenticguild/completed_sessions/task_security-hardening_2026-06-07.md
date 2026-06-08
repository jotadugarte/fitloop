# Security Hardening (Group A)

## Overview
This session covers security hardening, logs compliance, and traffic control. We will:
1. Configure strict parameter logging filtering to avoid writing sensitive payment and user info to logs (PCI-DSS compliance).
2. Install and configure `rack-attack` to rate-limit authentication (sign-in/sign-up) and payment checkout/confirmation routes.
3. Implement an environment-controlled maintenance mode (`MAINTENANCE_MODE=true`) that renders a clean Hotwire-friendly view with a `503 Service Unavailable` status, bypassing checks for admins, active health checks, and essential asset requests.

---

## Architectural Decisions & Edge Cases

### 1. Log Filtering (PCI-DSS compliance)
- **Sensitive Parameters**: ONVO checkout parameters such as `:card_number`, `:card_holder_name`, `:card_cvv`, `:sinpe_mobile_number`, `:sinpe_identification` must be masked.
- **Log configuration**: We will update `config/initializers/filter_parameter_logging.rb` to filter both generic keys (`:card_number`, `:holder_name`, `:mobile_number`, `:identification`) and their specific variants (`:card_holder_name`, `:sinpe_mobile_number`, `:sinpe_identification`, `:card_cvv`).

### 2. Rate Limiting (`rack-attack`)
- **Integration**: We will add `gem "rack-attack"` to the Gemfile.
- **Configuration**:
  - Limit login attempts (`POST /iniciar-sesion`) and registration attempts (`POST /crear-cuenta`) per IP.
  - Limit payment requests (`POST /checkout/pagar`, `POST /checkout/pagos/*/sinpe`, `POST /checkout/pagos/*/tarjeta`) per IP.
  - **Bypasses**: Safely allow localhost/development environment requests or internal testing IP lists if needed.
- **Return Type**: Respond with `429 Too Many Requests`. The response can be a plain text "Retry later" or a simple JSON/HTML page.

### 3. Maintenance Mode
- **Controller Action**: We will add a `before_action :check_maintenance_mode` hook in `ApplicationController`.
- **Bypasses**:
  - Health check path: `request.path == "/up"`.
  - Admin users: `current_user&.admin?`.
  - Devise sessions path (sign in, sign out) so admins can authenticate:
    - Path starts with `/iniciar-sesion` or `/cerrar-sesion` or the controller is `users/sessions`.
  - Asset requests: Requests for CSS/JS assets (e.g. starting with `/assets/`).
- **Response**: Render an HTML page `app/views/errors/maintenance.html.erb` using the `minimal` layout with status `503 Service Unavailable`.

---

## Risk Matrix
- **Risk 1: Locking out Admins in Maintenance Mode** - If the admin is not logged in, they might not be able to access the log-in page to authenticate.
  - *Mitigation*: Ensure Devise login routes `/iniciar-sesion` (GET/POST) and sign out routes `/cerrar-sesion` are completely bypassed from maintenance mode check.
- **Risk 2: Uptime checks reporting failures** - If the uptime monitor targets `/` or `/up` and gets a 503 during maintenance.
  - *Mitigation*: Ensure `/up` (the health check endpoint) is completely bypassed.
- **Risk 3: Rate limit false positives** - Legitimate webhook calls or user flows blocked.
  - *Mitigation*: Ensure `POST /webhooks/onvo` is NOT rate limited by the general IP-based payment limits (or limit it with very generous thresholds compared to card/sinpe confirmation checks).

---

## Domain Model
*(No new domain models or Value Objects are introduced. This is standard application routing, middleware, and configuration hardening).*

---

<implementation_plan>
  <phase name="Phase 1: Test Baseline &amp; Log Filtering (PCI-DSS)">
    <step id="1" status="complete">
      <instruction>Run the existing RSpec tests to verify the current codebase is fully green.</instruction>
      <command>bundle exec rspec</command>
    </step>
    <step id="2" status="complete">
      <instruction>Write a test (unit or request spec) verifying that sensitive parameter keys (such as :card_number, :sinpe_identification) are filtered out from Rails parameter logs.</instruction>
    </step>
    <step id="3" status="complete">
      <instruction>Update `config/initializers/filter_parameter_logging.rb` to mask card/sinpe sensitive keys: `:card_number`, `:holder_name`, `:card_holder_name`, `:mobile_number`, `:sinpe_mobile_number`, `:identification`, `:sinpe_identification`.</instruction>
    </step>
    <step id="4" status="complete">
      <instruction>Verify that the new log filtering tests pass successfully.</instruction>
      <command>bundle exec rspec</command>
    </step>
  </phase>

  <phase name="Phase 2: Rate Limiting with rack-attack">
    <step id="5" status="complete">
      <instruction>Add `gem "rack-attack"` to the Gemfile and install it.</instruction>
      <command>bundle install</command>
    </step>
    <step id="6" status="complete">
      <instruction>Write a request spec in `spec/requests/rate_limiting_spec.rb` to assert that hitting auth/payment endpoints excessively triggers a 429 status code (expecting failure because rack-attack is not yet configured).</instruction>
    </step>
    <step id="7" status="complete">
      <instruction>Create `config/initializers/rack_attack.rb` and configure limits for auth and payment POST requests (e.g. 5 requests per minute per IP for sensitive paths, or other appropriate limits) and enable Rack::Attack middleware in `config/application.rb`.</instruction>
    </step>
    <step id="8" status="complete">
      <instruction>Verify that the rate limiting request tests now pass successfully.</instruction>
      <command>bundle exec rspec spec/requests/rate_limiting_spec.rb</command>
    </step>
  </phase>

  <phase name="Phase 3: Fast Maintenance Mode">
    <step id="9" status="complete">
      <instruction>Write request specs in `spec/requests/maintenance_mode_spec.rb` to verify 503 is returned under `MAINTENANCE_MODE=true`, and that bypasses (admin user, `/up`, static assets, `/iniciar-sesion`) function correctly (expecting failure because maintenance mode is not yet implemented).</instruction>
    </step>
    <step id="10" status="complete">
      <instruction>Create the maintenance view in `app/views/errors/maintenance.html.erb` with clean styles (and es/en localization strings in `config/locales/`).</instruction>
    </step>
    <step id="11" status="complete">
      <instruction>Implement `check_maintenance_mode` in `ApplicationController` as a before_action, handling bypasses (admin, health check, login, assets).</instruction>
    </step>
    <step id="12" status="complete">
      <instruction>Verify that maintenance mode tests pass and run the entire test suite to confirm 100% coverage and no regressions.</instruction>
      <command>bundle exec rspec</command>
    </step>
  </phase>
</implementation_plan>

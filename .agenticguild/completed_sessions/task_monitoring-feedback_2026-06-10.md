# Active Session: Monitoring and Feedback (task_monitoring-feedback.md)

This task covers the implementation of production monitoring (Honeybadger exception tracking, system metrics alerts), email/Discord notifications, a user feedback capture system, and several key UI/UX improvements.

> [!IMPORTANT]
> **Pre-requisite**: This task depends on the completed infrastructure setup in [task_email-discord-setup.md](file:///home/jader/proyectos/fitloop/.agenticguild/active_sessions/task_email-discord-setup.md).


---

## 🔍 UI/UX Audit & Study

After reviewing the application layouts, styling system, and workshop routes, we are implementing the following UX/UI improvements:

### 1. Landing Page / Tool Hub (`/`)
*   **Observations**: The dashboard grid is clean, showcasing fiTLoop and a disabled "synCLoop" card.
*   **Enhancements**:
    *   Add hover transitions with subtle lift and glow on the active card.
    *   For disabled/upcoming cards, include a "Notificarme al lanzar" tooltip or small modal input (future backlog) to increase early engagement.
    *   **Footer Integration**: Add a clean footer containing links to terms/privacy and a prominent "Únete a nuestro Discord" community invite link to centralize support.

### 2. Ephemeral Workshop Layout (`/taller`)
*   **Observations**: High-quality CAD-blueprint styling matching IBM Plex Sans. Sheet inventory and input DXF sections are collapsed by default to save vertical space.
*   **Enhancements**:
    *   **Pan & Zoom on Preview**: Implement a custom Stimulus controller `svg-pan-zoom` that enables interactive panning and zooming (via drag/scroll wheel) on the SVG nesting preview.
    *   **Feedback & Help Integration**: Add a round **Floating Action Button (FAB)** in the bottom-right corner with a glassmorphism blur (`backdrop-filter`) and CAD-blue styling. It opens a native HTML5 `<dialog>` form that includes a Discord community invite link ("Soporte en Discord") alongside the feedback form.

### 3. Billing & Checkout Flow
*   **Observations**: Uses ONVO and SINPE payment intents, defaulting currencies based on Cloudflare GeoIP headers.
*   **Enhancements**:
    *   Add trust badges (secure card logos, SINPE logo) to the paywall cart to increase conversion confidence.
    *   Include a short tooltip explaining *why* CRC or USD was selected (e.g., "Moneda determinada según tu ubicación").

---

## 🛠️ Discord & Email Setup Instructions

1. **Discord Webhook (Alerts)**:
   - If you do not have a server, click the **+ (Add a Server)** button in Discord to create a free server.
   - Right-click your server's name, choose **Server Settings** -> **Integrations** -> click **Webhooks** -> click **New Webhook**.
   - Select the target text channel (e.g., `#alertas-modusloop`).
   - Name it (e.g., `moduSLoop Bot`) and copy the **Webhook URL**. Set it as `DISCORD_WEBHOOK_URL` in production env.
2. **Discord Invite Link (Support)**:
   - Generate an invitation link to your Discord server.
   - **Crucial**: Edit the invite link settings to set **Expire After: Never** and **Max Number of Uses: No Limit** to prevent the link from breaking.
   - Add this invite URL as the environment variable `DISCORD_INVITE_URL` or load a configured default.
3. **Brevo SMTP Variables (Sending Emails)**:
   - In Coolify, configure environment variables: `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` matching your Brevo credentials.
4. **Cloudflare Email Routing (Receiving Emails)**:
   - In Cloudflare DNS -> **Email Routing**, configure routing rules to redirect `soporte@modusloop.com`, `facturacion@modusloop.com`, and `admin@modusloop.com` to your real Gmail address.
5. **Brevo SPF/DKIM DNS (Email Legitimacy)**:
   - Add the TXT records provided by Brevo to your Cloudflare DNS settings to authorize Brevo to send emails on behalf of `modusloop.com`.

## 🧱 Domain Model (CbC)

To align with the Clean-by-Construction (CbC) paradigm, we define the core domain entities and value objects for the feedback system:

### Entities

#### 1. Feedback
*   **Responsibility**: Represents user-submitted feedback, capturing the user's input, context, and status.
*   **Invariants**:
    *   Must have a message of 5 to 5000 characters.
    *   Must have a valid category/type: `"suggestion"`, `"bug"`, or `"other"`.
    *   Must have a valid status: `"pending"`, `"reviewed"`, or `"archived"`.
    *   If submitted anonymously, `email` must be present and valid.
    *   If submitted by an authenticated user, `user_id` should associate the feedback to that user.

### Value Objects / Branded Types
These are pure Ruby types used to represent domain values with strict validations:

*   **`Feedback::Message`**: Wraps the textual content of the feedback. Enforces length constraints (5..5000 characters) and strips surrounding whitespace.
*   **`Feedback::Category`**: Wraps the category (`suggestion`, `bug`, `other`). Enforces inclusion logic.
*   **`Feedback::Status`**: Wraps the current resolution status (`pending`, `reviewed`, `archived`). Defaults to `pending`.
*   **`Feedback::SenderEmail`**: Wraps and validates the email address format if provided.
*   **`Feedback::GuestContext`**: Wraps guest metadata (IP, User Agent, source page URL) to assist administrators in diagnosing issues.

---

## 📋 Work Plan & Proposed Changes

### Phase 1: Database & Backend Foundation
#### 1. [NEW] Database Migration
- Create `feedbacks` table:
  ```ruby
  create_table :feedbacks do |t|
    t.references :user, null: true, foreign_key: true
    t.string :email                     # For anonymous users
    t.string :feedback_type, null: false # suggestion, bug, other
    t.text :message, null: false
    t.string :source_url
    t.string :status, null: false, default: "pending"
    t.jsonb :guest_metadata, default: {} # ip, user_agent, workspace_id
    t.timestamps
  end
  ```

#### 2. [NEW] `Feedback` Model (`app/models/feedback.rb`)
- Model validations:
  - `message` presence, length: 5..5000.
  - `feedback_type` inclusion in `["suggestion", "bug", "other"]`.
  - `status` inclusion in `["pending", "reviewed", "archived"]`.
  - `email` format validation (only if present).

#### 3. [NEW] Notification Dispatcher (`app/services/notifications/dispatcher.rb`)
- Standard Net::HTTP helper to send a POST body payload to `ENV["DISCORD_WEBHOOK_URL"]` asynchronously.
- Deliver an email to `soporte@modusloop.com` using Action Mailer.

### Phase 2: Frontend Integration
#### 4. [NEW] Feedback Modal view & FAB Button
- Place the Floating Action Button (FAB) in `app/views/layouts/application.html.erb`.
- Style it in `app/assets/stylesheets/application.css` with a nice blur, circular outline, hover animation, and a letter/message icon.
- Build the native HTML5 `<dialog>` in `app/views/shared/_feedback_dialog.html.erb` with custom styling (blueprint accent color).
- Include the "Soporte en Discord" link prominently inside the dialog using `ENV["DISCORD_INVITE_URL"]`.
- Form inputs:
  - Select: Type (Sugerencia, Error, Otro)
  - Input: Email (only shown/required if `!user_signed_in?`)
  - Textarea: Message / Idea
- Submit form asynchronously via Turbo.

#### 5. [NEW] `FeedbacksController` (`app/controllers/feedbacks_controller.rb`)
- Action `create` that parses request data (IP, User Agent), instantiates `Feedback`, saves it, dispatches notifications, and returns a Turbo Stream to close the dialog and show a toast/flash message.

### Phase 3: Admin Management Dashboard
#### 6. [NEW] Admin Feedbacks Controller & Views (`app/controllers/admin/feedbacks_controller.rb`)
- Actions: `index` (list with filters for type/status), `update` (to change status to `reviewed` or `archived`), `destroy`.
- Add "Feedback" tab to `app/views/layouts/admin.html.erb` navigation.
- Simple, clean table view with search.

### Phase 4: UI/UX Improvements
#### 7. Landing Page Hover Transitions & Footer
- Update `.tool-card` hover and lift styling in `app/assets/stylesheets/application.css`.
- Add a visual footer to the Landing layout (`app/views/home/index.html.erb` or layouts) with a Discord join button.
#### 8. SVG Pan & Zoom Stimulus Controller
- Implement `app/javascript/controllers/svg_pan_zoom_controller.js`.
- Update `app/views/projects/_nesting_preview.html.erb` to connect the controller.
#### 9. Billing Trust Badges & Tooltips
- Update paywall layout in `app/views/download_paywall/show.html.erb` to display secure card/SINPE trust badges and geographical determination tooltips.

### Phase 5: Production Observability
#### 10. Honeybadger Exception Tracking
- Add `gem "honeybadger"` to `Gemfile`.
- Run initializer template, configured to initialize only when `HONEYBADGER_API_KEY` is present.
- Ensure it is silent in development/testing.

---

## 🧪 Verification & Test Suite
- **Unit Specs**: Validate `Feedback` invariants, validation error conditions, and email/type validations.
- **Request Specs**: Test asynchronous submission of feedback, notifications routing (mocking Discord POST and Mailer deliveries), and IP metadata tracking.
- **System Specs**: End-to-end integration test of clicking the FAB button, submitting the form, verifying database persistence, and displaying the success flash message.
- **Coverage**: Maintain strict SimpleCov 100% test coverage enforcement.

---

<implementation_plan>
  <phase name="Phase 1: DB & backend initialization">
    <step>
      <description>Write unit specs first for the Feedback model (spec/models/feedback_spec.rb) defining all validations, enums, and default status.</description>
    </step>
    <step>
      <description>Generate database migration to create feedbacks table with fields user_id, email, feedback_type, message, source_url, status, guest_metadata.</description>
    </step>
    <step>
      <description>Create Feedback model with validations for presence/length of message, inclusion of feedback_type and status, and email format validation.</description>
    </step>
    <step>
      <description>Create Action Mailer for Admin notifications to dispatch email on feedback submission.</description>
    </step>
    <step>
      <description>Implement Discord notification helper service app/services/notifications/dispatcher.rb using Net::HTTP to dispatch JSON webhooks with Embed structures (Red for bug, Blue for suggestion, Grey for other) when ENV['DISCORD_WEBHOOK_URL'] is set.</description>
    </step>
  </phase>
  <phase name="Phase 2: Controller & Front-end Integration">
    <step>
      <description>Write request specs (spec/requests/feedbacks_spec.rb) for feedback creation verifying success response, IP/UA extraction, and email/Discord dispatch.</description>
    </step>
    <step>
      <description>Implement FeedbacksController (app/controllers/feedbacks_controller.rb) with a create action saving feedback, internally resolving user_id and email if user is signed in, sanitizing/filtering sensitive guest metadata before saving, and returning Turbo Stream updates.</description>
    </step>
    <step>
      <description>Create app/views/shared/_feedback_dialog.html.erb markup with the dialog form, types selection, conditional email field (hidden and not required if user_signed_in?), and message textarea. Include the support Discord invite link inside the help text.</description>
    </step>
    <step>
      <description>Render FAB button inside app/views/layouts/application.html.erb toolbar or root container, styled to float in bottom-right corner using CSS glassmorphism rules in app/assets/stylesheets/application.css. Exclude the FAB from rendering when in the admin namespace.</description>
    </step>
  </phase>
  <phase name="Phase 3: Admin Panel">
    <step>
      <description>Write request specs for Admin::FeedbacksController verifying authorized access only.</description>
    </step>
    <step>
      <description>Create Admin::FeedbacksController (app/controllers/admin/feedbacks_controller.rb) and views (index.html.erb) to view, filter, review, and archive feedback.</description>
    </step>
    <step>
      <description>Update Admin layout navigation (app/views/layouts/admin.html.erb) to show the Feedback management link.</description>
    </step>
  </phase>
  <phase name="Phase 4: UI/UX Enhancements">
    <step>
      <description>Improve hover lift and glow transitions on tool hub card `.tool-card` in application.css.</description>
    </step>
    <step>
      <description>Add a landing page footer in app/views/home/index.html.erb displaying the Discord invite link using ENV['DISCORD_INVITE_URL'] or a default fallback URL.</description>
    </step>
    <step>
      <description>Build Stimulus controller app/javascript/controllers/svg_pan_zoom_controller.js supporting dragging and mouse-wheel scrolling for SVG preview.</description>
    </step>
    <step>
      <description>Integrate the svg_pan_zoom_controller in app/views/projects/_nesting_preview.html.erb.</description>
    </step>
    <step>
      <description>Add trust badges (SINPE, Visa/Mastercard logos) and a geographic billing explanation tooltip in app/views/download_paywall/show.html.erb.</description>
    </step>
  </phase>
  <phase name="Phase 5: Exception Tracking & QA Verification">
    <step>
      <description>Add honeybadger gem to Gemfile and run bundle install.</description>
    </step>
    <step>
      <description>Configure Honeybadger initializer to only report errors when HONEYBADGER_API_KEY environment variable is present (production-only) and ensure it respects the application parameter filtering for sensitive fields.</description>
    </step>
    <step>
      <description>Write a comprehensive system spec (spec/system/feedback_flow_spec.rb) E2E testing the FAB button click, modal dialog popup, submission, and confirmation toast.</description>
    </step>
    <step>
      <description>Validate 100% test coverage with SimpleCov and execute tests locally.</description>
    </step>
  </phase>
</implementation_plan>




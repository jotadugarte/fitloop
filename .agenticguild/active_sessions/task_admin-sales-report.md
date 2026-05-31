<task_session>
  <metadata>
    <task_name>Admin ventas / reporte de pagos</task_name>
    <type>Feature</type>
    <req_id>REQ-FIT-ADMIN-001</req_id>
    <roadmap_item>Admin ventas / reporte de pagos (Pending #2)</roadmap_item>
  </metadata>

  <working_notes>
    ## Context & Goal
    Implement the sales reporting and payment history admin view under `/admin/ventas`.
    This dashboard will display all payment attempts (succeeded, pending, failed) with purchaser info, financial details, and support CSV exports.
    It will also serve as the source of truth for the administrator to manually generate electronic invoices (facturas/tiquetes) in Costa Rica.

    ## Costa Rica Electronic Invoicing Requirements (Hacienda)
    To facilitate off-platform electronic invoicing in Costa Rica, the sales report must display the following database fields from the `payments` table:
    1. **Purchaser Information (Receptor):**
       - Name (`purchaser_name`)
       - Email (`purchaser_email`) - essential for XML transmission.
       - Identification Details (For SINPE: `sinpe_transfer_identification`, `sinpe_transfer_mobile_number`).
    2. **Transaction Information:**
       - Purchase Reference (`purchase_reference`) - a 12-digit unique ID.
       - Gateway Reference (`onvo_payment_intent_id`) - for payment reconciliation in ONVO.
       - Payment Method (`payment_method` - `card_crc`, `card_usd`, `sinpe_crc`).
       - Status (`status` - `succeeded`, `pending`, `failed`).
       - Date (`paid_at` or `created_at` in the user's timezone/local CR timezone).
    3. **Financial Breakdown:**
       - Base Price / List Price (`list_price`)
       - Discount (`discount_amount`) - notably for SINPE CRC discount.
       - Subtotal (`subtotal`) - net amount before taxes.
       - Sales Tax (IVA 13%) (`tax_amount`) - applied when `currency` is `crc` and `iva_applicable` is true.
       - Total (`total_amount`).
       - Currency (`currency` - `usd` or `crc`). Note: If the transaction is in USD, the administrator needs the date to look up the official BCCR exchange rate.

    ## Domain Model
    - **Entity:** `Payment`
      - **Responsibility:** Records transaction outcomes for single downloads or plan subscriptions (pending, succeeded, failed).
      - **Invariants:**
        - Succeeded payments must have `paid_at` present.
        - Payments made via the ONVO gateway must have `onvo_payment_intent_id`, `onvo_mode`, and `gateway_status`.
        - Single download payments must have a generated 12-digit `purchase_reference` code before creation.
        - Persists a CAByS code (`cabys_code`) set to `8314200000100` for all payments.
        - Translates internal product descriptions to user-friendly Spanish names in views and CSV exports: `"single_download"` -> `"Procesamiento de anidado DXF"`, and `"plan_X_months"` -> `"Suscripción mensual - Plan de X meses"` (or `"1 mes"` for plan_1_months).
      - **Value Objects / Branded Types:**
        - `Billing::PaymentMethod` (wraps String: `card_usd`, `card_crc`, `sinpe_crc`)
        - `Billing::Currency` (wraps String: `usd`, `crc`)
        - `Billing::Money` (wraps BigDecimal value + `Billing::Currency` pair)

    ## User Interface & Features
    - Route: `/admin/ventas` (managed by `Admin::VentasController`, inheriting from `Admin::BaseController`).
    - Sidebar/Navigation link under `/admin` layout.
    - Payments Table:
      - Filters: Status (All, Succeeded, Pending, Failed), Payment Method, Date Range.
      - Sorting: Chronological by default (`created_at` or `paid_at` descending).
      - Columns: Reference, Purchaser (Name/Email), Date, Method, Subtotal, Discount, Tax, Total, CAByS, Status, Actions.
      - Detail Modal/Drawer: Complete details of a specific payment (including SINPE ID, ONVO Intent ID, User ID, and CAByS Code).
    - CSV Export:
      - Trigger link: "Exportar CSV".
      - Generates a CSV file with all matching payments containing all relevant columns (including CAByS code and Costa Rica invoicing data) for easy import into external accounting software.
  </working_notes>

  <implementation_plan>
    <step id="1" status="complete">
      <description>Create database migration to add `cabys_code` (string) to `payments` table and run it.</description>
    </step>
    <step id="2" status="pending">
      <description>Update payment models, services (e.g., StartOnvoCheckout, SimulateSingleDownload, SimulatePlanPurchase) and specs to populate and validate the `cabys_code` field upon payment creation.</description>
    </step>
    <step id="3" status="pending">
      <description>Write controller request specs for Admin::VentasController verifying authentication (non-admins get 404, admins get 200) and basic actions.</description>
    </step>
    <step id="4" status="pending">
      <description>Add routes for `/admin/ventas` and `/admin/ventas/exportar` under the `:admin` namespace in config/routes.rb.</description>
    </step>
    <step id="5" status="pending">
      <description>Implement Admin::VentasController with index and export actions, supporting status filtering, search/date filters, and paginated payments query.</description>
    </step>
    <step id="6" status="pending">
      <description>Update the Admin dashboard skeleton layout to link to the new Ventas page and remove "Próximamente" from the Ventas link.</description>
    </step>
    <step id="7" status="pending">
      <description>Create views for Admin::Ventas index page, including filters, payment table, total metrics summary cards, and detail modal/drawers.</description>
    </step>
    <step id="8" status="pending">
      <description>Implement CSV generation in a helper or service class, exporting all fields necessary for Costa Rica invoicing including `cabys_code`.</description>
    </step>
    <step id="9" status="pending">
      <description>Run all specs (including database and request tests) and perform manual visual checks on the admin views.</description>
    </step>
  </implementation_plan>
</task_session>

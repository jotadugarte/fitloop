# Active Session: Email and Discord Setup (task_email-discord-setup.md)

<metadata>
  <task_name>Email and Discord Setup</task_name>
  <type>Chore</type>
  <status>Implementación completada con éxito</status>
</metadata>

This task covers the infrastructure and DevOps configuration for outbound transactional SMTP emails, Cloudflare inbound email routing, SPF/DKIM validation, and Discord Server integrations.

---

## 📋 DevOps Setup Checklist

### 1. Cloudflare Inbound Email Routing
- [ ] Enable Cloudflare Email Routing in your domain settings.
- [ ] Add destination address for your personal Gmail.
- [ ] Create custom routing rules:
  - `soporte@modusloop.com` -> redirect to Gmail.
  - `facturacion@modusloop.com` -> redirect to Gmail.
  - `admin@modusloop.com` -> redirect to Gmail.

### 2. Brevo SMTP & DNS Configuration
- [ ] Log in to Brevo, retrieve SMTP credentials (address, port, username, API key/password).
- [ ] Add the DNS records (SPF, DKIM, DMARC TXT records) provided by Brevo inside Cloudflare DNS to legitimize outbound emails on behalf of `modusloop.com`.

### 3. Discord Server & Integration Setup
- [ ] Create a new Discord Server (if you don't have one).
- [ ] Create a text channel for alerts (e.g., `#alertas-modusloop`).
- [ ] In channel settings -> **Integrations** -> **Webhooks**, click **New Webhook**. Copy the Webhook URL.
- [ ] Generate a permanent invite link to your Discord server (set Expire After: Never, Max Uses: No Limit).

### 4. Coolify Environment Variables
- [ ] In the Coolify panel for the production app, configure:
  - `SMTP_ADDRESS` -> (Brevo SMTP host)
  - `SMTP_PORT` -> (Brevo SMTP port)
  - `SMTP_USER` -> (Brevo login/username)
  - `SMTP_PASSWORD` -> (Brevo API key/password)
  - `DISCORD_WEBHOOK_URL` -> (copied webhook URL)
  - `DISCORD_INVITE_URL` -> (permanent invite URL)

---

## 🧪 Verification Plan
- Send a verification email to `admin@modusloop.com` and verify it is received in the Gmail inbox.
- Trigger a registration confirmation email from production to verify transactional SMTP sending works under Brevo.
- Smoke test webhook delivery to `#alertas-modusloop` using curl.

---

<implementation_plan>
  <step id="1" status="complete">Configure Cloudflare Email Routing rules mapping soporte@, facturacion@, and admin@ to Gmail.</step>
  <step id="2" status="complete">Verify receiving a test email sent directly to admin@modusloop.com in Gmail.</step>
  <step id="3" status="complete">Add Brevo SPF, DKIM, and DMARC TXT DNS records to Cloudflare to authorize email sending.</step>
  <step id="4" status="complete">Configure SMTP environment variables (SMTP_ADDRESS, SMTP_PORT, SMTP_USER, SMTP_PASSWORD) in Coolify production app settings.</step>
  <step id="5" status="complete">Verify SMTP outbound mail delivery from the production environment (e.g. via Devise confirmation resends or console checks).</step>
  <step id="6" status="complete">Create Discord server, alert channel, copy Webhook URL, and generate permanent invite link.</step>
  <step id="7" status="complete">Configure Discord environment variables (DISCORD_WEBHOOK_URL, DISCORD_INVITE_URL) in Coolify production app settings.</step>
  <step id="8" status="complete">Verify Discord webhook delivery by sending a smoke test message using a curl POST to the webhook URL.</step>
</implementation_plan>

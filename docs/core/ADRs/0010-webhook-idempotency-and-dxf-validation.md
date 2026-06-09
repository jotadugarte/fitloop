# ADR-0010: Webhook Idempotency and DXF Validation

**Status:** Accepted  
**Date:** 2026-06-08

## Context and problem statement

This ADR addresses two security and concurrency issues identified in the billing and upload pipelines:
1. **Webhook Concurrency**: The ONVO webhook fulfillment endpoint was vulnerable to concurrent duplicate request payloads. Simultaneous identical callback requests could run the fulfillment or failure logic concurrently, leading to duplicate database records (e.g., `DownloadGrant` creation) or unique constraint crashes.
2. **DXF Upload Validation**: Uploaded DXF files lacked strict size and structure integrity sanitization in Rails, risking system slowdowns or downstream parser crashes when dealing with extremely large or corrupt files.

## Decision drivers

- Ensure absolute idempotency for payment webhook fulfillment, preventing double downloads or race conditions.
- Prevent local storage growth from malicious or oversized files.
- Fail fast and return clean localized alerts to users uploading invalid or corrupt DXF drawings.

## Considered options

1. **Option A** – Handle idempotency using simple status checks on the payment record without locking, and limit file sizes on the client side only.
2. **Option B (Chosen)** – Implement database pessimistic locking (`lock!`) on the payment record during fulfillment and failure workflows, and execute server-side validation checking size, extension, and the `SECTION` marker in both models and controllers.

## Decision outcome

**Chosen option:** Option B.

### Rationale
- **Pessimistic Locking**: `Billing::FulfillPayment` and `Billing::FailPayment` lock the target `Payment` record inside a transaction. If the payment has already transitioned to a terminal status (succeeded or failed), subsequent concurrent requests are caught, return status `:already_fulfilled` or `:already_terminal`, and exit early.
- **Double-Layer DXF Sanitization**: 
  - Controllers reject invalid uploads (size > 10MB, non-`.dxf` extension, missing `SECTION` content marker) and redirect with a flash message.
  - The `Project` model runs `validate_input_dxf_files` on both unsaved changes and persisted attachments as a fallback database-level integrity guarantee.

### Positive consequences

- Webhook concurrency race conditions are mitigated directly at the database level.
- Uploaded files are validated early before consuming storage resources.
- Clear error handling for concurrent requests, avoiding duplicate webhook logs and double download grants.

### Negative consequences

- Database pessimistic locking introduces a small blocking overhead on concurrent execution threads (mitigated since ONVO webhooks are low-concurrency event handlers).

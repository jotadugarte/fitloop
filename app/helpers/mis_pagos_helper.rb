# frozen_string_literal: true

# [REQ-FIT-BILL-002] Mis pagos presentation helpers.
module MisPagosHelper
  def mis_pagos_download_status_label(row)
    if row.pending_lock_expired?
      t("billing.mis_pagos.download_status.unconfirmed")
    elsif row.pending?
      t("billing.mis_pagos.download_status.pending")
    elsif row.downloadable?
      t("billing.mis_pagos.download_status.available")
    else
      t("billing.mis_pagos.download_status.expired")
    end
  end

  def mis_pagos_download_status_class(row)
    if row.pending_lock_expired?
      "status-badge--failed"
    elsif row.pending?
      "status-badge--processing"
    elsif row.downloadable?
      "status-badge--completed"
    else
      "status-badge--failed"
    end
  end

  def mis_pagos_download_row_class(row)
    base = "mis-pagos-download-row"
    if row.pending_lock_expired?
      "#{base} mis-pagos-download-row--pending-unconfirmed"
    elsif row.pending?
      "#{base} mis-pagos-download-row--pending-awaiting"
    elsif row.downloadable?
      "#{base} mis-pagos-download-row--ready"
    else
      "#{base} mis-pagos-download-row--expired"
    end
  end

  def mis_pagos_payment_status_label(payment)
    if payment.superseded?
      t("billing.mis_pagos.status.superseded")
    else
      t("billing.mis_pagos.status.#{payment.status}")
    end
  end

  def mis_pagos_payment_status_badge_class(payment)
    return "status-badge--failed" if payment.superseded?

    mis_pagos_payment_status_badge_class_for_status(payment.status)
  end

  def mis_pagos_payment_status_badge_class_for_status(status)
    case status.to_s
    when "succeeded" then "status-badge--completed"
    when "pending" then "status-badge--processing"
    else "status-badge--failed"
    end
  end

  def mis_pagos_sinpe_primary_action(payment)
    if payment.sinpe_awaiting_transfer?
      {
        label: t("billing.checkout.onvo.sinpe_continue"),
        url: checkout_processing_path(payment),
        testid: "mis-pagos-sinpe-continue"
      }
    else
      {
        label: t("billing.mis_pagos.sinpe_resume"),
        url: checkout_path(nesting_run_id: payment.nesting_run_id, payment_id: payment.id),
        testid: "mis-pagos-sinpe-resume"
      }
    end
  end

  def mis_pagos_row_project_title(row)
    title = row.nesting_run&.project&.title.to_s.strip
    title.presence || t("workspace.default_title")
  end

  def mis_pagos_row_payment_details_line(row)
    parts = [mis_pagos_row_reference(row), mis_pagos_row_payment_method(row)].compact
    return nil if parts.empty?

    safe_join(parts, tag.span(" · ", class: "mis-pagos-download-row__fact-sep", aria: { hidden: true }))
  end

  def mis_pagos_row_nested_at(row)
    l_in_user_zone(row.sort_at, format: :short, user: current_user)
  end

  def mis_pagos_row_reference(row)
    payment = row.payment_for_display
    return nil unless payment&.single_download?

    if payment.purchase_reference.present?
      key = row.pending? ? "row_reference_attempt" : "row_reference_payment"
      t("billing.mis_pagos.#{key}", reference: payment.purchase_reference)
    else
      legacy_key = row.pending? ? "row_reference_attempt_legacy" : "row_reference_payment_legacy"
      t("billing.mis_pagos.#{legacy_key}", id: payment.id)
    end
  end

  def mis_pagos_payment_reference_label(payment)
    return nil unless payment.single_download?
    return nil if payment.purchase_reference.blank?

    t("billing.mis_pagos.payment_reference", reference: payment.purchase_reference)
  end

  def mis_pagos_row_payment_method(row)
    payment = row.payment_for_display
    return nil unless payment

    t("billing.checkout.#{payment.payment_method}")
  end

  def mis_pagos_row_amount(row)
    payment = row.payment_for_display
    return nil unless payment

    mis_pagos_payment_amount_label(payment)
  end

  def mis_pagos_payment_amount_label(payment)
    amount = payment.total_amount || payment.amount
    formatted = number_with_precision(
      amount,
      precision: amount.to_f == amount.to_i ? 0 : 2,
      delimiter: ",",
      separator: "."
    )
    "#{payment.currency.upcase} #{formatted}"
  end
end

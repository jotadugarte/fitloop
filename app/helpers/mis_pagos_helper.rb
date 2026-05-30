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

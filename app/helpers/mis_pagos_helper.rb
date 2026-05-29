# frozen_string_literal: true

# [REQ-FIT-BILL-002] Mis pagos presentation helpers.
module MisPagosHelper
  def mis_pagos_download_status_label(row)
    if row.pending?
      t("billing.mis_pagos.download_status.pending")
    elsif row.downloadable?
      t("billing.mis_pagos.download_status.available")
    else
      t("billing.mis_pagos.download_status.expired")
    end
  end

  def mis_pagos_download_status_class(row)
    if row.pending?
      "status-badge--processing"
    elsif row.downloadable?
      "status-badge--completed"
    else
      "status-badge--failed"
    end
  end

  def mis_pagos_download_row_class(row)
    base = "mis-pagos-download-row"
    if row.pending?
      "#{base} mis-pagos-download-row--pending"
    elsif row.downloadable?
      "#{base} mis-pagos-download-row--ready"
    else
      "#{base} mis-pagos-download-row--expired"
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

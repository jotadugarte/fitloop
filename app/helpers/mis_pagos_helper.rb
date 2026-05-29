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
      "mis-pagos-download-card__badge--pending"
    elsif row.downloadable?
      "mis-pagos-download-card__badge--available"
    else
      "mis-pagos-download-card__badge--expired"
    end
  end

  def mis_pagos_download_card_class(row)
    base = "mis-pagos-download-card"
    if row.pending?
      "#{base} mis-pagos-download-card--pending"
    elsif row.downloadable?
      "#{base} mis-pagos-download-card--ready"
    else
      "#{base} mis-pagos-download-card--expired"
    end
  end

  def mis_pagos_payment_amount_label(payment)
    "#{payment.currency.upcase} #{number_with_delimiter(payment.amount, delimiter: ',')}"
  end
end

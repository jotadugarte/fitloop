# frozen_string_literal: true

module MisPagos
  # [REQ-FIT-BILL-003] Download retained nested DXF from Mis pagos (D54, D45).
  class DownloadsController < ApplicationController
    include RequiresBillingConfirmation

    before_action :require_operational_user!
    before_action :set_grant

    def show
      payload = Billing::RetainedDownload.serve!(grant: @grant)
      send_data(
        payload[:data],
        filename: payload[:filename],
        type: payload[:content_type],
        disposition: "attachment"
      )
    rescue Billing::RetainedDownload::Expired
      render plain: t("billing.download.retention_expired"), status: :forbidden
    rescue Billing::RetainedDownload::MissingBlob
      head :not_found
    end

    private

    def require_operational_user!
      return if current_user.operationally_active?

      redirect_to edit_user_registration_path, alert: t("billing.suspended")
    end

    def set_grant
      @grant = DownloadGrant.single_purchase.find_by(id: params[:id])
      return head(:forbidden) if @grant.nil? || @grant.user_id != current_user.id
    end
  end
end

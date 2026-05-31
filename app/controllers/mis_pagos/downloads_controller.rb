# frozen_string_literal: true

module MisPagos
  # [REQ-FIT-BILL-003] Download retained nested DXF from Mis pagos (D54, D45).
  class DownloadsController < ApplicationController
    include RequiresBillingConfirmation

    before_action :require_operational_user!
    before_action :set_grant

    def show
      payload = Billing::RetainedDownload.serve!(grant: @grant)

      Analytics::TrackEvent.call(
        "download_completed",
        user_id: current_user&.id,
        anonymous_session_key: session[:anonymous_session_key],
        project_id: @grant.nesting_run&.project_id,
        nesting_run_id: @grant.nesting_run_id,
        idempotency_key: "download_completed_grant_#{@grant.id}_#{Time.current.to_i / 10}",
        ip: request.remote_ip,
        user_agent: request.user_agent,
        country_code: Analytics::ResolveCountry.call(request),
        locale: I18n.locale.to_s
      )

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
      head :forbidden unless @grant&.user_id == current_user.id
    end
  end
end

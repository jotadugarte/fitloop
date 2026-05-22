# frozen_string_literal: true

# [REQ-FIT-BILL-001] Nested DXF download requires grant, plan quota, or paywall (D42).
module RequiresNestedDownloadAuthorization
  extend ActiveSupport::Concern

  private

  def authorize_nested_download!
    return head(:not_found) unless @project.nested_dxf.attached?

    @nesting_run = nesting_run_for_download
    unless @nesting_run
      redirect_to workshop_path, alert: t("projects.show.nested_dxf_unavailable")
      return
    end

    return redirect_to(download_paywall_workshop_path) if current_user.nil?
    unless current_user.billing_ready?
      return redirect_to(email_confirmation_pending_path, alert: t("devise.failure.unconfirmed"))
    end

    return if valid_download_token?(@nesting_run)
    return if Billing::Entitlement.can_download?(user: current_user, nesting_run: @nesting_run)

    redirect_to download_paywall_workshop_path
  end

  def nesting_run_for_download
    @project.nesting_runs
             .where(status: Nesting::StatusMapper::DOWNLOADABLE_RUN_STATUSES)
             .order(id: :desc)
             .first
  end

  def valid_download_token?(run)
    return false if params[:download_token].blank? || current_user.nil?

    payload = Billing::DownloadToken.verify(params[:download_token])
    payload[:user_id] == current_user.id && payload[:nesting_run_id] == run.id
  rescue Billing::DownloadToken::InvalidToken
    false
  end
end

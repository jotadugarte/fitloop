# frozen_string_literal: true

# [REQ-FIT-BILL-001] Nested DXF download requires grant, plan quota, or paywall (D42).
module RequiresNestedDownloadAuthorization
  extend ActiveSupport::Concern

  private

  def authorize_nested_download!
    return head(:not_found) unless @project.nested_dxf.attached?

    run = @project.nesting_runs.order(id: :desc).first
    return head(:not_found) unless run

    return redirect_to(download_paywall_project_path(@project)) if current_user.nil?
    unless current_user.billing_ready?
      return redirect_to(email_confirmation_pending_path, alert: t("devise.failure.unconfirmed"))
    end

    return if Billing::Entitlement.can_download?(user: current_user, nesting_run: run)

    redirect_to download_paywall_project_path(@project)
  end
end

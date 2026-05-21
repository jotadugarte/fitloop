# frozen_string_literal: true

# [REQ-FIT-BILL-001] Paywall before nested DXF download (D42).
class DownloadPaywallController < ApplicationController
  include SetsWorkspaceProject

  before_action :set_workspace_project

  def show
    @nesting_run = @project.nesting_runs.order(id: :desc).first
  end
end

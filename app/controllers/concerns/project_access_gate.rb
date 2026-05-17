# frozen_string_literal: true

# [REQ-FIT-UI-003] Session flag after successful user or admin PIN verification.
module ProjectAccessGate
  extend ActiveSupport::Concern

  included do
    helper_method :project_access_granted?
  end

  def project_access_granted?(project)
    session[:project_access]&.fetch(project.id.to_s, false) == true
  end

  def grant_project_access!(project)
    session[:project_access] ||= {}
    session[:project_access][project.id.to_s] = true
  end

  def require_project_access!(project)
    return if project_access_granted?(project)

    @project = project
    render "projects/pin_gate", status: :ok
  end
end

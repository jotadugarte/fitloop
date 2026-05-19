# frozen_string_literal: true

module ProjectSpecFactory
  DEFAULT_SHEET_STOCK = {
    width_mm: 1000,
    height_mm: 2000,
    quantity: 1,
    sort_order: 0
  }.freeze

  module_function

  def create!(title:, pin: nil, sheet_stocks_attributes: nil, ephemeral: true, **attrs)
    record_attrs = {
      title: title,
      ephemeral: ephemeral,
      sheet_stocks_attributes: sheet_stocks_attributes || { "0" => DEFAULT_SHEET_STOCK.dup },
      **attrs
    }
    record_attrs[:pin] = pin if pin.present?
    Project.create!(record_attrs)
  end
end

RSpec.configure do |config|
  config.include(Module.new do
    def create_project_for_spec!(**kwargs)
      bind_workspace = kwargs.delete(:bind_workspace)
      bind_workspace = true if bind_workspace.nil?

      project = ProjectSpecFactory.create!(**kwargs)
      bind_workspace_session!(project) if bind_workspace
      project
    end

    def start_setup_session!
      get start_project_path
      follow_redirect!
      Project.find(session[:workspace_project_id])
    end

    def bind_workspace_session!(project)
      return unless project.ephemeral?
      return unless respond_to?(:get)

      start_setup_session!
      stale_id = session[Workspace::SESSION_KEY]
      Project.find_by(id: stale_id)&.destroy! if stale_id.present? && stale_id != project.id
      session[Workspace::SESSION_KEY] = project.id
      session[:project_access] ||= {}
      session[:project_access][project.id.to_s] = true
    end
  end)
end

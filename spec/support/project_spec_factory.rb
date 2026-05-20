# frozen_string_literal: true

module ProjectSpecFactory
  DEFAULT_SHEET_STOCK = {
    width_mm: 1000,
    height_mm: 2000,
    quantity: 1,
    sort_order: 0
  }.freeze

  module_function

  def create!(title:, sheet_stocks_attributes: nil, ephemeral: true, **attrs)
    attrs.delete(:pin)

    Project.create!(
      title: title,
      ephemeral: ephemeral,
      sheet_stocks_attributes: sheet_stocks_attributes || { "0" => DEFAULT_SHEET_STOCK.dup },
      **attrs
    )
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

      get rails_health_check_path
      session[Workspace::SESSION_KEY] = project.id
    end
  end)
end

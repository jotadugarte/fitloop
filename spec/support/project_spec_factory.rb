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
    raise ArgumentError, "create_project_for_spec! only supports ephemeral projects" if ephemeral == false

    attrs.delete(:pin)
    attrs.delete(:bind_workspace)

    Project.create!(
      title: title,
      ephemeral: true,
      sheet_stocks_attributes: sheet_stocks_attributes || { "0" => DEFAULT_SHEET_STOCK.dup },
      **attrs
    )
  end

  def apply_attrs!(project, **kwargs)
    kwargs.delete(:pin)
    kwargs.delete(:bind_workspace)
    kwargs[:ephemeral] = true

    sheet_stocks = kwargs.delete(:sheet_stocks_attributes)
    project.update!(kwargs)
    if sheet_stocks
      project.sheet_stocks.destroy_all
      project.update!(sheet_stocks_attributes: sheet_stocks)
      project.reload
    else
      ensure_default_sheet_stocks!(project)
    end
    project
  end

  def ensure_default_sheet_stocks!(project)
    return project if project.sheet_stocks.exists?

    project.update!(sheet_stocks_attributes: { "0" => DEFAULT_SHEET_STOCK.dup })
    project.reload
  end
end

RSpec.configure do |config|
  config.include(Module.new do
    def create_project_for_spec!(**kwargs)
      bind_workspace = kwargs.delete(:bind_workspace)
      can_bind_session = respond_to?(:get) || respond_to?(:visit)
      bind_workspace = can_bind_session if bind_workspace.nil?

      return ProjectSpecFactory.create!(**kwargs) unless bind_workspace

      project = begin_workspace_session!
      ProjectSpecFactory.apply_attrs!(project, **kwargs)
    end

    def start_setup_session!
      get start_project_path
      follow_redirect!
      Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID) ||
        Project.find(session[Workspace::SESSION_KEY])
    end

    # Session bind must go through the controller (Rails 8 request specs do not persist
    # arbitrary session writes). Start flow creates and binds an ephemeral draft.
    def begin_workspace_session!
      if respond_to?(:visit)
        visit start_project_path
        ProjectSpecFactory.ensure_default_sheet_stocks!(Project.ephemeral.order(:id).last!)
      else
        get start_project_path
        follow_redirect!
        project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID) ||
                  Project.find(session[Workspace::SESSION_KEY])
        ProjectSpecFactory.ensure_default_sheet_stocks!(project)
      end
    end

    def start_ephemeral_workspace!
      begin_workspace_session!
    end

    def bind_workspace_session!(project)
      raise ArgumentError, "bind_workspace_session! requires an ephemeral project" unless project.ephemeral?

      if respond_to?(:get)
        get start_project_path
        follow_redirect!
        session[Workspace::SESSION_KEY] = project.id
        get rails_health_check_path
      elsif respond_to?(:visit)
        visit start_project_path
        Project.ephemeral.order(:id).last!.tap { |p| raise "bind mismatch" unless p.id == project.id }
      end
    end
  end)
end

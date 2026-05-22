# frozen_string_literal: true

# [REQ-FIT-UI-005] [REQ-FIT-DXF-002] Save layer role picks before locale redirect (setup / workshop).
class PersistWorkspaceLayerSelectionDraft
  def self.call(session:, params:, tab_id: nil)
    new(session: session, params: params, tab_id: tab_id).call
  end

  def initialize(session:, params:, tab_id: nil)
    @session = session
    @params = params
    @tab_id = tab_id
  end

  def call
    project = Workspace.any_bound_project(@session, prefer_tab_id: @tab_id)
    return false unless project

    permitted = extract_project_layers
    return false if permitted.blank?
    return false if would_wipe_configured_layers?(project, permitted)

    ProjectLayerSelection.apply!(project: project, raw_params: permitted)
    true
  end

  private

  def extract_project_layers
    raw = @params[:project_layers]
    return nil if raw.blank?

    raw.respond_to?(:permit!) ? raw.permit!.to_h : raw.to_h
  end

  def would_wipe_configured_layers?(project, permitted)
    return false unless project.project_layers.where.not(layer_role: nil).exists?

    !selection_in_params?(permitted)
  end

  def selection_in_params?(permitted)
    permitted.any? do |_attachment_key, attrs|
      next false unless attrs.is_a?(Hash)

      return true if attrs["primary_layer_id"].present?

      attrs.any? do |layer_key, layer_params|
        layer_key != "primary_layer_id" &&
          layer_params.is_a?(Hash) &&
          layer_params["auxiliary"] == "1"
      end
    end
  end
end

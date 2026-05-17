# frozen_string_literal: true

# [REQ-FIT-DXF-001] Layer checklist built from union of uploaded DXF layer names.
class ProjectLayersController < ApplicationController
  before_action :set_project
  before_action -> { require_project_access!(@project) }

  def index
    Dxf::LayerSync.call(@project)
    @project_layers = @project.project_layers.order(:layer_name)
    @readiness = ProjectReadinessValidator.validate(@project)
  end

  def update
    update_layer_inclusions!
    redirect_to project_layers_path(@project), notice: t("project_layers.updated")
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def update_layer_inclusions!
    permitted = params.fetch(:project_layers, {}).permit!
    permitted.each do |id, attrs|
      layer = @project.project_layers.find_by(id: id)
      next unless layer

      layer.update!(included: attrs[:included] == "1")
    end
  end
end

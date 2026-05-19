# frozen_string_literal: true

# [REQ-FIT-DXF-001] Layer checklist built from union of uploaded DXF layer names.
class ProjectLayersController < ApplicationController
  include StartsNesting

  before_action :set_project
  before_action -> { require_project_access!(@project) }

  def index
    Dxf::LayerSync.call(@project)
    @project_layers = @project.project_layers.order(:layer_name)
    @readiness = ProjectReadinessValidator.validate(@project)
  end

  def update
    update_layer_inclusions!

    readiness = ProjectReadinessValidator.validate(@project)
    unless readiness.ok?
      redirect_to project_layers_path(@project), alert: readiness.errors.join(" ")
      return
    end

    start_nesting_for!(@project)
    redirect_to @project
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def update_layer_inclusions!
    permitted = params.fetch(:project_layers, {}).permit!
    @project.project_layers.find_each do |layer|
      attrs = permitted[layer.id.to_s]
      layer.update!(included: attrs.present? && attrs[:included] == "1")
    end
  end
end

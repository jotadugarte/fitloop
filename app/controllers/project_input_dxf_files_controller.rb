# frozen_string_literal: true

# [REQ-FIT-DXF-001] Multi-DXF upload for a project.
class ProjectInputDxfFilesController < ApplicationController
  before_action :set_project

  def create
    files = Array(params[:files]).compact
    if files.blank?
      redirect_to project_layers_path(@project), alert: t("project_layers.upload.missing")
      return
    end

    files.each { |file| @project.input_dxf.attach(file) }
    Dxf::LayerSync.call(@project)
    redirect_to project_layers_path(@project), notice: t("project_layers.upload.created")
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end

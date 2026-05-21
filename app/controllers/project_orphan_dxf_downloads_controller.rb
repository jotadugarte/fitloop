# frozen_string_literal: true

# [REQ-FIT-NEST-003] Download DXF for a single orphan piece.
class ProjectOrphanDxfDownloadsController < ApplicationController
  include SetsWorkspaceProject

  before_action :set_workspace_project

  def show
    orphan = orphan_presenter.find_by_piece_index(params[:piece_index])
    return head(:not_found) if orphan.nil? || !orphan.exportable?

    export_path = Dxf::OrphanPieceExporter.export(rings: orphan.rings)
    payload = File.binread(export_path)
    send_data(
      payload,
      filename: download_filename(orphan),
      type: "application/dxf",
      disposition: "attachment"
    )
  rescue Dxf::OrphanPieceExporter::Error
    head(:unprocessable_content)
  ensure
    File.delete(export_path) if defined?(export_path) && export_path && File.exist?(export_path)
  end

  private

  def orphan_presenter
    Nesting::OrphansPresenter.for(@project)
  end

  def download_filename(orphan)
    "pieza_#{orphan.display_number}.dxf"
  end
end

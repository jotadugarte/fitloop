# frozen_string_literal: true

# [REQ-FIT-VAL-001] Pre-flight: block nesting when layers or extractable pieces are missing.
class ProjectReadinessValidator
  Result = Struct.new(:ok?, :errors, keyword_init: true)

  def self.validate(project)
    new(project).validate
  end

  def initialize(project)
    @project = project
  end

  def validate
    errors = []
    errors << I18n.t("project_readiness.no_sheet_stocks") unless sheet_stocks?
    errors << I18n.t("project_readiness.no_layers_selected") unless selected_layers?
    errors.concat(missing_primary_layer_errors)
    errors << I18n.t("project_readiness.no_extractable_pieces") if selected_layers? && extractable_piece_count.zero?
    errors << I18n.t("project_readiness.unresolved_gaps") if selected_layers? && unresolved_gaps?

    Result.new(ok?: errors.empty?, errors: errors)
  end

  private

  def unresolved_gaps?
    @project.project_layers.where(included: true).any? do |layer|
      report = Nesting::GapReport.from_json(layer.gaps_detected)
      report.unresolved?(auto_close_gaps: !!layer.auto_close_gaps)
    end
  end

  def sheet_stocks?
    @project.sheet_stocks.exists?
  end

  def selected_layers?
    @project.project_layers.where(included: true).exists?
  end

  # [REQ-FIT-DXF-002] Included auxiliary layers require a primary on the same DXF file.
  def missing_primary_layer_errors
    attachment_ids = @project.project_layers
      .where(included: true, layer_role: :auxiliary)
      .where.not(active_storage_attachment_id: nil)
      .distinct
      .pluck(:active_storage_attachment_id)

    return [] if attachment_ids.empty?

    message = I18n.t("project_readiness.primary_layer_required")
    attachment_ids.filter_map do |attachment_id|
      primary_set = @project.project_layers.exists?(
        active_storage_attachment_id: attachment_id,
        included: true,
        layer_role: :primary
      )
      message unless primary_set
    end
  end

  def extractable_piece_count
    return 0 if @project.input_dxf_attachments.blank?

    if per_file_layers?
      count_with_per_file_layers
    else
      count_with_union_layers
    end
  end

  def per_file_layers?
    @project.project_layers.where.not(active_storage_attachment_id: nil).exists?
  end

  def count_with_union_layers
    layer_names = Dxf::PieceCounter.layer_names_for_count(@project.project_layers)
    return 0 if layer_names.empty?

    with_downloaded_dxf_paths do |paths|
      return 0 if paths.blank?

      Dxf::PieceCounter.count(paths: paths, layer_names: layer_names)
    end
  end

  def count_with_per_file_layers
    total = 0
    @project.input_dxf_attachments.each do |attachment|
      layer_names = Dxf::PieceCounter.layer_names_for_count(
        @project.project_layers.where(active_storage_attachment_id: attachment.id)
      )
      next if layer_names.empty?

      total += with_downloaded_path(attachment) do |path|
        Dxf::PieceCounter.count(paths: [ path ], layer_names: layer_names)
      end
    end
    total
  end

  def with_downloaded_path(attachment)
    tempfile = Tempfile.new([ "fitloop_dxf", ".dxf" ], Dir.tmpdir)
    tempfile.binmode
    attachment.download { |chunk| tempfile.write(chunk) }
    tempfile.flush
    yield tempfile.path
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  def with_downloaded_dxf_paths
    return yield [] if @project.input_dxf_attachments.blank?

    tempfiles = []
    paths = @project.input_dxf_attachments.map do |attachment|
      tempfile = Tempfile.new([ "fitloop_dxf", ".dxf" ], Dir.tmpdir)
      tempfiles << tempfile
      tempfile.binmode
      attachment.download { |chunk| tempfile.write(chunk) }
      tempfile.flush
      tempfile.path
    end
    yield paths
  ensure
    tempfiles&.each do |tempfile|
      tempfile.close
      tempfile.unlink
    end
  end
end

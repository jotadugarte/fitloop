# frozen_string_literal: true

module Nesting
  # [REQ-FIT-SPLIT-001] [REQ-FIT-VAL-001] Resolves manual orphans after DXF update and pre-flight.
  class ConfirmManualOrphanResolution
    Result = Struct.new(:ok?, :errors, keyword_init: true)

    def self.call(project:, orphan_resolution:)
      new(project: project, orphan_resolution: orphan_resolution).call
    end

    def initialize(project:, orphan_resolution:)
      @project = project
      @orphan_resolution = orphan_resolution
    end

    def call
      readiness = ProjectReadinessValidator.validate(@project)
      return failure(readiness.errors) unless readiness.ok?

      orphan_row = orphan_row_for_resolution
      return failure([ I18n.t("nesting.split.manual.orphan_geometry_missing") ]) if orphan_row.nil?

      layer_name = primary_layer_name
      return failure([ I18n.t("project_readiness.no_layers_selected") ]) if layer_name.blank?

      if MotherPieceStillPresent.call(
        project: @project,
        mother_rings: orphan_row.rings,
        layer_name: layer_name
      )
        return failure([ I18n.t("nesting.split.manual_mother_still_present") ])
      end

      @orphan_resolution.update!(resolution_state: :resolved)
      append_session_workflow_log!
      Result.new(ok?: true, errors: [])
    end

    private

    def orphan_row_for_resolution
      Nesting::OrphansPresenter.for(@project).items.find do |orphan|
        orphan.piece_key.to_s == @orphan_resolution.piece_key.to_s
      end
    end

    def primary_layer_name
      @project.project_layers.where(included: true).order(:layer_name).pick(:layer_name)
    end

    def failure(errors)
      Result.new(ok?: false, errors: errors)
    end

    def append_session_workflow_log!
      log = Array(@project.session_workflow_log)
      log << {
        "event" => "manual_orphan_resolved",
        "piece_key" => @orphan_resolution.piece_key,
        "at" => Time.current.iso8601
      }
      @project.update!(session_workflow_log: log)
    end
  end
end

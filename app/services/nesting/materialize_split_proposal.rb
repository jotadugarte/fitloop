# frozen_string_literal: true

module Nesting
  # [REQ-FIT-SPLIT-001] Persists derived pieces and resolves the mother orphan after accept.
  class MaterializeSplitProposal
    def self.call(project:, orphan_resolution:, proposal:)
      new(project: project, orphan_resolution: orphan_resolution, proposal: proposal).call
    end

    def initialize(project:, orphan_resolution:, proposal:)
      @project = project
      @orphan_resolution = orphan_resolution
      @proposal = proposal
    end

    def call
      raise ArgumentError, "cannot accept infeasible split proposal" if @proposal.split_not_feasible?

      ActiveRecord::Base.transaction do
        @proposal.update!(status: :accepted)
        materialize_derived_pieces!
        @orphan_resolution.update!(resolution_state: :resolved)
        append_session_workflow_log!
      end
    end

    private

    def materialize_derived_pieces!
      @project.derived_pieces.where(parent_piece_key: @orphan_resolution.piece_key).delete_all
      primary_layer = mother_primary_layer_name

      Array(@proposal.child_piece_geometries).each_with_index do |child, index|
        suffix = child["label"].presence || @proposal.labels.fetch(index)
        geometry_json = { "rings" => child.fetch("rings") }
        geometry_json["primary_layer_name"] = primary_layer if primary_layer.present?

        @project.derived_pieces.create!(
          parent_piece_key: @orphan_resolution.piece_key,
          label: piece_label(suffix),
          geometry_json: geometry_json,
          decorations_json: Array(child["decorations"]),
          sort_order: index
        )
      end
    end

    def mother_primary_layer_name
      @mother_primary_layer_name ||= @project.project_layers.find_by(
        included: true,
        layer_role: :primary
      )&.layer_name.to_s.presence
    end

    def piece_label(suffix)
      piece_number = @orphan_resolution.piece_key.to_i + 1
      "Pieza-#{piece_number}#{suffix}"
    end

    def append_session_workflow_log!
      log = Array(@project.session_workflow_log)
      log << {
        "event" => "split_accepted",
        "piece_key" => @orphan_resolution.piece_key,
        "split_proposal_id" => @proposal.id,
        "at" => Time.current.iso8601
      }
      log << {
        "event" => "splits_ready_for_nest",
        "piece_key" => @orphan_resolution.piece_key,
        "derived_piece_count" => @project.derived_pieces.count,
        "at" => Time.current.iso8601
      }
      @project.update!(session_workflow_log: log)
    end
  end
end

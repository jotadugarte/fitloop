# frozen_string_literal: true

module Nesting
  # [REQ-FIT-CLI-001] Builds config.json payload for nesting_engine CLI.
  class ConfigBuilder
    def self.build(project:, work_dir:, input_paths:)
      new(project: project, work_dir: work_dir, input_paths: input_paths).build
    end

    def initialize(project:, work_dir:, input_paths:)
      @project = project
      @work_dir = Pathname(work_dir)
      @input_paths = input_paths
    end

    def build
      output_dir = @work_dir.join("output")
      job_params = JobParameters.from_project(@project)
      payload = {
        project_id: @project.id.to_s,
        sheet_stocks: sheet_stock_payload,
        output_dir: output_dir.to_s
      }.merge(job_params.to_config_hash)
      merge_input_layer_config!(payload)
      merge_split_config!(payload)
      payload
    end

    private

    def merge_input_layer_config!(payload)
      if per_file_layers?
        payload[:input_files] = input_files_payload
      else
        payload[:input_dxf_paths] = @input_paths.map(&:to_s)
        payload[:included_layers] = included_layer_names
        auto_close = auto_close_layer_names
        payload[:auto_close_layers] = auto_close if auto_close.any?
      end
    end

    def per_file_layers?
      @project.project_layers.where.not(active_storage_attachment_id: nil).exists?
    end

    def input_files_payload
      attachments = @project.input_dxf_attachments.to_a
      @input_paths.map(&:to_s).zip(attachments).map do |path, attachment|
        file_entry = { path: path }
        merge_layer_config_for_file!(file_entry, attachment)
        file_entry
      end
    end

    def merge_layer_config_for_file!(file_entry, attachment)
      primary = primary_layer_for(attachment)
      if primary
        file_entry[:primary_layer] = primary.layer_name
        auxiliary = auxiliary_layers_for(attachment)
        file_entry[:auxiliary_layers] = auxiliary if auxiliary.any?

        auto_close_layers = []
        auto_close_layers << primary.layer_name if primary.auto_close_gaps
        file_entry[:auto_close_layers] = auto_close_layers if auto_close_layers.any?
        return
      end

      layers = included_layers_records_for(attachment)
      file_entry[:included_layers] = layers.pluck(:layer_name)
      auto_close_layers = layers.where(auto_close_gaps: true).pluck(:layer_name)
      file_entry[:auto_close_layers] = auto_close_layers if auto_close_layers.any?
    end

    def primary_layer_for(attachment)
      @project.project_layers.find_by(
        active_storage_attachment_id: attachment.id,
        included: true,
        layer_role: :primary
      )
    end

    def auxiliary_layers_for(attachment)
      @project.project_layers
        .where(included: true, active_storage_attachment_id: attachment.id, layer_role: :auxiliary)
        .order(:layer_name)
        .pluck(:layer_name)
    end

    def included_layers_for(attachment)
      @project.project_layers
        .where(included: true, active_storage_attachment_id: attachment.id)
        .order(:layer_name)
        .pluck(:layer_name)
    end

    def included_layers_records_for(attachment)
      @project.project_layers
        .where(included: true, active_storage_attachment_id: attachment.id)
        .order(:layer_name)
    end

    def included_layer_names
      @project.project_layers.where(included: true).order(:layer_name).pluck(:layer_name)
    end

    def auto_close_layer_names
      @project.project_layers.where(included: true, auto_close_gaps: true).order(:layer_name).pluck(:layer_name)
    end

    def merge_split_config!(payload)
      derived = derived_pieces_payload
      return if derived.empty?

      payload[:excluded_piece_keys] = excluded_piece_keys
      payload[:derived_pieces] = derived
      cuts = split_cut_segments_payload
      payload[:split_cut_segments] = cuts if cuts.present?
    end

    def excluded_piece_keys
      @project.derived_pieces.order(:parent_piece_key).distinct.pluck(:parent_piece_key)
    end

    def derived_pieces_payload
      @project.derived_pieces.order(:sort_order).map do |piece|
        payload = {
          parent_piece_key: piece.parent_piece_key,
          label: piece.label,
          sort_order: piece.sort_order,
          rings: piece.geometry_json.fetch("rings")
        }
        decorations = Array(piece.decorations_json)
        payload[:decorations] = decorations if decorations.any?
        primary_layer = piece.geometry_json["primary_layer_name"]
        payload[:primary_layer_name] = primary_layer if primary_layer.present?
        payload
      end
    end

    def split_cut_segments_payload
      SplitProposal
        .joins(:orphan_resolution)
        .where(orphan_resolutions: { project_id: @project.id }, status: :accepted)
        .flat_map { |proposal| Array(proposal.cut_segments) }
    end

    def sheet_stock_payload
      @project.sheet_stocks.order(:sort_order).map do |stock|
        SheetStockRow.from_sheet_stock(stock).to_config_hash
      end
    end
  end
end

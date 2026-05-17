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
      {
        project_id: @project.id.to_s,
        input_dxf_paths: @input_paths.map(&:to_s),
        included_layers: included_layer_names,
        sheet_stocks: sheet_stock_payload,
        kerf_mm: @project.kerf_mm,
        margin_mm: @project.margin_mm,
        curve_tolerance_mm: @project.curve_tolerance_mm,
        sheet_gap_mm: @project.sheet_gap_mm,
        time_limit_sec: @project.nesting_time_limit_sec,
        output_dir: output_dir.to_s
      }
    end

    private

    def included_layer_names
      @project.project_layers.where(included: true).order(:layer_name).pluck(:layer_name)
    end

    def sheet_stock_payload
      @project.sheet_stocks.order(:sort_order).map do |stock|
        {
          width_mm: stock.width_mm,
          height_mm: stock.height_mm,
          quantity: stock.quantity,
          sort_order: stock.sort_order
        }
      end
    end
  end
end

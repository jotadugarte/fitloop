# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"

module Nesting
  # [REQ-FIT-SPLIT-001] Invokes nesting_engine plan_splits mode for one orphan resolution.
  class SplitPlannerRunner
    DEFAULT_SCRIPT = Rails.root.join("nesting_engine/nest.py").freeze

    def self.call(orphan_resolution:, invoke: nil)
      new(orphan_resolution: orphan_resolution, invoke: invoke).call
    end

    def initialize(orphan_resolution:, invoke: nil)
      @orphan_resolution = orphan_resolution
      @project = orphan_resolution.project
      @invoke = invoke
    end

    def call
      work_dir = prepare_work_dir
      input_paths = materialize_input_dxfs!(work_dir)
      write_config!(work_dir, input_paths)
      run_cli!(work_dir)
      load_proposal!(work_dir)
    end

    private

    def work_dir_path
      Pathname(Rails.root.join("tmp/split_plans", @orphan_resolution.id.to_s))
    end

    def prepare_work_dir
      path = work_dir_path
      FileUtils.mkdir_p(path)
      path
    end

    def materialize_input_dxfs!(work_dir)
      inputs_dir = work_dir.join("inputs")
      FileUtils.mkdir_p(inputs_dir)

      @project.input_dxf_attachments.map do |attachment|
        filename = attachment.blob.filename.to_s
        destination = inputs_dir.join(filename)
        File.open(destination, "wb") do |file|
          attachment.download { |chunk| file.write(chunk) }
        end
        destination
      end
    end

    def write_config!(work_dir, input_paths)
      output_dir = work_dir.join("output")
      FileUtils.mkdir_p(output_dir)
      config = ConfigBuilder.build(project: @project, work_dir: work_dir, input_paths: input_paths).merge(
        "mode" => "plan_splits",
        "piece_keys" => [ @orphan_resolution.piece_key ]
      )
      File.write(work_dir.join("config.json"), JSON.pretty_generate(config))
    end

    def run_cli!(work_dir)
      config_path = work_dir.join("config.json")
      return @invoke.call(work_dir, config_path) if @invoke

      env = Dxf::Python.subprocess_env
      command = [ Dxf::Python.executable, DEFAULT_SCRIPT.to_s, config_path.to_s ]
      exit_status = nil

      Open3.popen3(env, *command) do |_stdin, _stdout, _stderr, wait_thr|
        exit_status = wait_thr.value.exitstatus
      end

      raise "split planner CLI failed with exit #{exit_status}" unless exit_status.to_i.zero?

      exit_status
    end

    def load_proposal!(work_dir)
      preview_path = work_dir.join("output", "split_preview.json")
      raise "split_preview.json missing" unless preview_path.file?

      preview = JSON.parse(preview_path.read)
      proposal = Array(preview["proposals"]).find do |row|
        row["piece_key"].to_s == @orphan_resolution.piece_key.to_s
      end
      raise "split preview missing proposal for #{@orphan_resolution.piece_key}" unless proposal

      proposal
    end
  end
end

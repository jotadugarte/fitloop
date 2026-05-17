# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"

module Nesting
  # [REQ-FIT-CLI-001] Writes config.json, invokes nesting CLI, attaches nested.dxf.
  class CliRunner
    DEFAULT_SCRIPT = Rails.root.join("nesting_engine/nest.py").freeze

    Result = Struct.new(:exit_status, :work_dir, keyword_init: true)

    def self.call(nesting_run:, invoke: nil)
      new(nesting_run: nesting_run, invoke: invoke).call
    end

    def initialize(nesting_run:, invoke: nil)
      @nesting_run = nesting_run
      @project = nesting_run.project
      @invoke = invoke
    end

    def call
      work_dir = prepare_work_dir
      input_paths = materialize_input_dxfs!(work_dir)
      write_config!(work_dir, input_paths)

      exit_status = run_cli!(work_dir)
      attach_nested_dxf!(work_dir) if exit_status.zero?
      report = load_report(work_dir)
      finalize_run!(exit_status: exit_status, report: report)

      Result.new(exit_status: exit_status, work_dir: work_dir)
    end

    private

    def prepare_work_dir
      path = Rails.root.join("tmp/nesting_runs", @nesting_run.id.to_s)
      FileUtils.mkdir_p(path)
      Pathname(path)
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
      config = ConfigBuilder.build(project: @project, work_dir: work_dir, input_paths: input_paths)
      @nesting_run.update!(params_snapshot: config)

      path = work_dir.join("config.json")
      File.write(path, JSON.pretty_generate(config))
      path
    end

    def run_cli!(work_dir)
      config_path = work_dir.join("config.json")
      if @invoke
        return @invoke.call(work_dir, config_path)
      end

      _stdout, _stderr, status = Open3.capture3(
        Dxf::Python.subprocess_env,
        Dxf::Python.executable,
        DEFAULT_SCRIPT.to_s,
        config_path.to_s
      )
      status.exitstatus
    end

    def attach_nested_dxf!(work_dir)
      nested_path = work_dir.join("output", "nested.dxf")
      raise MissingOutputError, "nested.dxf not found" unless nested_path.file?

      @project.nested_dxf.attach(
        io: File.open(nested_path),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
    end

    def load_report(work_dir)
      report_path = work_dir.join("output", "report.json")
      return {} unless report_path.file?

      JSON.parse(report_path.read)
    end

    def finalize_run!(exit_status:, report:)
      terminal_status = map_terminal_status(exit_status: exit_status, report: report)
      @nesting_run.update!(
        status: terminal_status,
        report_json: report,
        finished_at: Time.current
      )
      @project.update!(status: terminal_status)
    end

    def map_terminal_status(exit_status:, report:)
      return "failed" unless exit_status.zero?

      report_status = report["status"].to_s
      return report_status if %w[completed partial failed].include?(report_status)

      "failed"
    end

    class MissingOutputError < StandardError; end
  end
end

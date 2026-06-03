# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"

module Nesting
  # [REQ-FIT-CLI-001] Writes config.json, invokes nesting CLI, attaches nested.dxf.
  class CliRunner
    DEFAULT_SCRIPT = Rails.root.join("nesting_engine/nest.py").freeze

    Result = Struct.new(:exit_status, :work_dir, keyword_init: true)

    def self.call(nesting_run:, invoke: nil, cancel_check: nil)
      new(nesting_run: nesting_run, invoke: invoke, cancel_check: cancel_check).call
    end

    # Reconcile a stuck processing run when CLI output exists on disk (missed finalize).
    def self.finalize_from_work_dir!(nesting_run:)
      new(nesting_run: nesting_run).finalize_from_work_dir!
    end

    def initialize(nesting_run:, invoke: nil, cancel_check: nil)
      @nesting_run = nesting_run
      @project = nesting_run.project
      @invoke = invoke
      @cancel_check = cancel_check
    end

    def call
      work_dir = prepare_work_dir
      input_paths = materialize_input_dxfs!(work_dir)
      write_config!(work_dir, input_paths)

      exit_status = run_cli!(work_dir)
      report = load_report(work_dir)
      terminal_status = StatusMapper.map(exit_status: exit_status, report: report, work_dir: work_dir)
      attach_outputs!(work_dir, terminal_status: terminal_status)
      finalize_run!(terminal_status: terminal_status, report: report)

      Result.new(exit_status: exit_status, work_dir: work_dir)
    end

    def finalize_from_work_dir!
      work_dir = work_dir_path
      return false unless work_dir.directory?

      report = load_report(work_dir)
      return false if report.empty?

      terminal_status = StatusMapper.map(exit_status: 0, report: report, work_dir: work_dir)
      attach_outputs!(work_dir, terminal_status: terminal_status)
      finalize_run!(terminal_status: terminal_status, report: report)
      true
    end

    private

    def work_dir_path
      Pathname(Rails.root.join("tmp/nesting_runs", @nesting_run.id.to_s))
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
      config = ConfigBuilder.build(project: @project, work_dir: work_dir, input_paths: input_paths)
      @nesting_run.update!(params_snapshot: config)

      path = work_dir.join("config.json")
      File.write(path, JSON.pretty_generate(config))
      path
    end

    def run_cli!(work_dir)
      config_path = work_dir.join("config.json")
      raise CancelledError if @cancel_check&.call

      @last_progress_percent = @project.progress_percent.to_i

      if @invoke
        exit_status = nil
        worker = Thread.new { exit_status = @invoke.call(work_dir, config_path) }
        return wait_with_progress_poll(work_dir) { worker.join(0.2) ? exit_status : nil }
      end

      env = Dxf::Python.subprocess_env
      command = [ Dxf::Python.executable, DEFAULT_SCRIPT.to_s, config_path.to_s ]

      Open3.popen3(env, *command) do |_stdin, _stdout, _stderr, wait_thr|
        pid = wait_thr.pid
        wait_with_progress_poll(work_dir) do
          if wait_thr.join(0.2)
            wait_thr.value.exitstatus
          elsif @cancel_check&.call
            Process.kill("TERM", pid)
            raise CancelledError
          end
        end
      end
    end

    def wait_with_progress_poll(work_dir)
      loop do
        raise CancelledError if @cancel_check&.call

        sync_progress!(work_dir)
        exit_status = yield
        return exit_status unless exit_status.nil?
      end
    end

    def sync_progress!(work_dir)
      snapshot = ProgressSnapshot.read(work_dir, last_percent: @last_progress_percent)
      return unless snapshot

      ProgressSync.call(project: @project, snapshot: snapshot, nesting_run: @nesting_run)
      @last_progress_percent = snapshot.percent
    end

    def attach_outputs!(work_dir, terminal_status:)
      attach_nested_dxf!(work_dir) if StatusMapper.attach_nested_output?(terminal_status: terminal_status, work_dir: work_dir)
      attach_placements_json!(work_dir) if attach_placements?(terminal_status: terminal_status, work_dir: work_dir)
    end

    def attach_placements?(terminal_status:, work_dir:)
      return false unless %w[completed partial].include?(terminal_status)

      work_dir.join("output", "placements.json").file?
    end

    def attach_nested_dxf!(work_dir)
      nested_path = work_dir.join("output", "nested.dxf")
      return unless nested_path.file?

      @project.nested_dxf.attach(
        io: File.open(nested_path),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
    end

    def attach_placements_json!(work_dir)
      placements_path = work_dir.join("output", "placements.json")
      return unless placements_path.file?

      @project.placements_json.attach(
        io: File.open(placements_path),
        filename: "placements.json",
        content_type: "application/json"
      )
    end

    def load_report(work_dir)
      report_path = work_dir.join("output", "report.json")
      return {} unless report_path.file?

      JSON.parse(report_path.read)
    end

    def finalize_run!(terminal_status:, report:)
      return unless @nesting_run.reload.status == "processing"

      @nesting_run.update!(
        status: terminal_status,
        report_json: report,
        finished_at: Time.current
      )
      @project.update!(status: terminal_status)
    end
  end
end

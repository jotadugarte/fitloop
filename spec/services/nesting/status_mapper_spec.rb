# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::StatusMapper do
  let(:work_dir) { Pathname(Dir.mktmpdir) }

  after do
    FileUtils.rm_rf(work_dir)
  end

  describe ".map [REQ-FIT-NEST-003]" do
    it "returns completed when exit is zero and report status is completed" do
      status = described_class.map(
        exit_status: 0,
        report: { "status" => "completed" },
        work_dir: work_dir
      )

      expect(status).to eq("completed")
    end

    it "returns partial when exit is zero and report status is partial" do
      status = described_class.map(
        exit_status: 0,
        report: { "status" => "partial", "orphans" => [ { "piece_index" => 0, "reason" => "oversized_for_sheet" } ] },
        work_dir: work_dir
      )

      expect(status).to eq("partial")
    end

    it "returns failed when exit is zero and report status is failed" do
      status = described_class.map(
        exit_status: 0,
        report: { "status" => "failed" },
        work_dir: work_dir
      )

      expect(status).to eq("failed")
    end

    it "returns failed when exit is non-zero and partial artifacts are missing" do
      status = described_class.map(exit_status: 1, report: {}, work_dir: work_dir)

      expect(status).to eq("failed")
    end

    it "returns failed when partial artifacts have corrupt report.json" do
      output_dir = work_dir.join("output")
      FileUtils.mkdir_p(output_dir)
      File.write(output_dir.join("nested.dxf"), "partial nest")
      File.write(output_dir.join("report.json"), "not-json")

      status = described_class.map(exit_status: 2, report: {}, work_dir: work_dir)

      expect(status).to eq("failed")
    end

    it "returns partial when exit is non-zero but partial artifacts exist" do
      output_dir = work_dir.join("output")
      FileUtils.mkdir_p(output_dir)
      File.write(output_dir.join("nested.dxf"), "partial nest")
      File.write(output_dir.join("report.json"), { status: "partial", orphans: [] }.to_json)

      status = described_class.map(exit_status: 2, report: {}, work_dir: work_dir)

      expect(status).to eq("partial")
    end
  end

  describe ".attach_nested_output? [REQ-FIT-NEST-003]" do
    it "allows attach for completed and partial when nested.dxf exists" do
      output_dir = work_dir.join("output")
      FileUtils.mkdir_p(output_dir)
      File.write(output_dir.join("nested.dxf"), "nested")

      expect(described_class.attach_nested_output?(terminal_status: "completed", work_dir: work_dir)).to be(true)
      expect(described_class.attach_nested_output?(terminal_status: "partial", work_dir: work_dir)).to be(true)
      expect(described_class.attach_nested_output?(terminal_status: "failed", work_dir: work_dir)).to be(false)
    end
  end
end

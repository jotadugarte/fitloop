# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ProgressSnapshot, "[REQ-FIT-JOB-001]" do
  let(:work_dir) { Pathname(Dir.mktmpdir) }
  let(:progress_path) { work_dir.join("output", "progress.json") }

  after do
    FileUtils.rm_rf(work_dir)
  end

  def write_progress(payload)
    FileUtils.mkdir_p(progress_path.dirname)
    progress_path.write(payload.to_json)
  end

  describe ".from_hash" do
    it "parses schema v1 and maps phase_id to i18n message" do
      snapshot = described_class.from_hash(
        {
          "version" => 1,
          "phase_id" => "fill",
          "percent" => 42,
          "pieces_total" => 10,
          "pieces_placed" => 4
        },
        last_percent: 0
      )

      expect(snapshot).to have_attributes(
        phase_id: "fill",
        percent: 42,
        message_key: "nesting.phase.fill",
        pieces_total: 10,
        pieces_placed: 4
      )
      expect(snapshot.message).to eq(I18n.t("nesting.phase.fill"))
    end

    it "uses message_key override when present" do
      I18n.backend.store_translations(:en, nesting: { custom: { progress: "Custom label" } })

      snapshot = described_class.from_hash(
        {
          "version" => 1,
          "phase_id" => "fill",
          "percent" => 50,
          "message_key" => "nesting.custom.progress"
        },
        last_percent: 0
      )

      expect(snapshot.message_key).to eq("nesting.custom.progress")
      expect(snapshot.message).to eq("Custom label")
    end

    it "returns nil when percent is negative or above 100" do
      expect(
        described_class.from_hash(
          { "version" => 1, "phase_id" => "fill", "percent" => -1 },
          last_percent: 0
        )
      ).to be_nil

      expect(
        described_class.from_hash(
          { "version" => 1, "phase_id" => "fill", "percent" => 101 },
          last_percent: 0
        )
      ).to be_nil
    end

    it "returns nil when percent regresses" do
      snapshot = described_class.from_hash(
        { "version" => 1, "phase_id" => "fill", "percent" => 30 },
        last_percent: 40
      )

      expect(snapshot).to be_nil
    end

    it "returns nil for unsupported schema version" do
      snapshot = described_class.from_hash(
        { "version" => 2, "phase_id" => "fill", "percent" => 10 },
        last_percent: 0
      )

      expect(snapshot).to be_nil
    end

    it "ignores non-integer piece counters" do
      snapshot = described_class.from_hash(
        {
          "version" => 1,
          "phase_id" => "fill",
          "percent" => 10,
          "pieces_total" => "many",
          "pieces_placed" => "few"
        },
        last_percent: 0
      )

      expect(snapshot.pieces_total).to be_nil
      expect(snapshot.pieces_placed).to be_nil
    end

    it "returns nil for unknown phase_id" do
      snapshot = described_class.from_hash(
        { "version" => 1, "phase_id" => "unknown", "percent" => 10 },
        last_percent: 0
      )

      expect(snapshot).to be_nil
    end
  end

  describe ".read" do
    before do
      I18n.backend.store_translations(
        :en,
        nesting: { phase: { extracting: "Extracting geometry" } }
      )
    end

    it "reads progress.json from work dir output" do
      write_progress(
        version: 1,
        phase_id: "extracting",
        percent: 10,
        pieces_total: 3
      )

      snapshot = described_class.read(work_dir, last_percent: 0)

      expect(snapshot).to have_attributes(
        phase_id: "extracting",
        percent: 10,
        pieces_total: 3
      )
    end

    it "returns nil when progress.json is missing" do
      expect(described_class.read(work_dir, last_percent: 0)).to be_nil
    end

    it "returns nil when progress.json is corrupt" do
      FileUtils.mkdir_p(progress_path.dirname)
      progress_path.write("{ not json")

      expect(described_class.read(work_dir, last_percent: 0)).to be_nil
    end
  end
end

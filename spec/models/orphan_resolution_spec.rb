# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrphanResolution, type: :model do
  let(:project) { create_project_for_spec!(title: "Split workspace", bind_workspace: false) }

  describe "associations [REQ-FIT-SPLIT-001] [REQ-FIT-DOM-001]" do
    it "[REQ-FIT-SPLIT-001] belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end

    it "[REQ-FIT-SPLIT-001] has many split_proposals" do
      expect(described_class.reflect_on_association(:split_proposals).macro).to eq(:has_many)
    end
  end

  describe "resolution_state [REQ-FIT-SPLIT-001]" do
    it "[REQ-FIT-SPLIT-001] allows pending, system_split, manual, and resolved" do
      expect(described_class.resolution_states.keys).to match_array(
        %w[pending system_split manual resolved]
      )
    end

    it "[REQ-FIT-SPLIT-001] defaults to pending" do
      resolution = described_class.new(project: project, piece_key: "blob-1:piece-7")

      expect(resolution.resolution_state).to eq("pending")
    end
  end

  describe "piece_key uniqueness [REQ-FIT-SPLIT-001]" do
    it "[REQ-FIT-SPLIT-001] enforces one row per piece_key per project" do
      described_class.create!(project: project, piece_key: "blob-1:piece-7", reason: "oversized_for_sheet")
      duplicate = described_class.new(project: project, piece_key: "blob-1:piece-7", reason: "oversized_for_sheet")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:piece_key, :taken)
    end
  end

  describe "ephemeral projects [REQ-FIT-SPLIT-001]" do
    it "[REQ-FIT-SPLIT-001] persists on ephemeral workspace projects" do
      expect(project).to be_ephemeral

      resolution = described_class.create!(
        project: project,
        piece_key: "blob-2:piece-1",
        reason: "no_sheet_capacity"
      )

      expect(resolution).to be_persisted
      expect(resolution.project_id).to eq(project.id)
    end
  end
end

RSpec.describe SplitProposal, type: :model do
  let(:project) { create_project_for_spec!(title: "Split preview", bind_workspace: false) }
  let(:resolution) do
    OrphanResolution.create!(
      project: project,
      piece_key: "blob-1:piece-3",
      reason: "oversized_for_sheet",
      resolution_state: :system_split
    )
  end

  describe "associations and status [REQ-FIT-SPLIT-001]" do
    it "[REQ-FIT-SPLIT-001] belongs to orphan_resolution" do
      expect(described_class.reflect_on_association(:orphan_resolution).macro).to eq(:belongs_to)
    end

    it "[REQ-FIT-SPLIT-001] allows draft, accepted, and rejected" do
      expect(described_class.statuses.keys).to match_array(%w[draft accepted rejected])
    end
  end
end

RSpec.describe DerivedPiece, type: :model do
  let(:project) { create_project_for_spec!(title: "Derived nest set", bind_workspace: false) }

  describe "associations [REQ-FIT-SPLIT-001]" do
    it "[REQ-FIT-SPLIT-001] belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end

    it "[REQ-FIT-SPLIT-001] stores parent_piece_key and label" do
      piece = described_class.create!(
        project: project,
        parent_piece_key: "blob-1:piece-3",
        label: "Pieza-3a",
        geometry_json: { "rings" => [[[0, 0], [100, 0], [100, 50], [0, 50], [0, 0]]] },
        sort_order: 0
      )

      expect(piece.parent_piece_key).to eq("blob-1:piece-3")
      expect(piece.label).to eq("Pieza-3a")
    end
  end
end

RSpec.describe Project, type: :model do
  describe "session_workflow_log [REQ-FIT-SPLIT-001]" do
    it "[REQ-FIT-SPLIT-001] defaults session_workflow_log to an empty array" do
      project = create_project_for_spec!(title: "Workflow log", bind_workspace: false)

      expect(project.session_workflow_log).to eq([])
    end
  end
end

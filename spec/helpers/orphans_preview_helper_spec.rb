# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrphansPreviewHelper, type: :helper do
  describe "#split_plan_preview_svg [REQ-FIT-SPLIT-001]" do
    let(:orphan) do
      Nesting::OrphansPresenter::Orphan.new(
        piece_index: 0,
        piece_key: "0",
        reason: "oversized_for_sheet",
        rings: [ [ [ 0.0, 0.0 ], [ 200.0, 0.0 ], [ 200.0, 80.0 ], [ 0.0, 80.0 ] ] ],
        width_mm: 200.0,
        height_mm: 80.0,
        offset_x_mm: 0.0,
        offset_y_mm: 0.0,
        resolution_state: "system_split",
        split_proposal: proposal
      )
    end
    let(:proposal) do
      SplitProposal.new(
        status: :draft,
        feasible: true,
        child_piece_geometries: [
          {
            "label" => "a",
            "rings" => [ [ [ 0.0, 0.0 ], [ 100.0, 0.0 ], [ 100.0, 50.0 ], [ 0.0, 50.0 ] ] ]
          },
          {
            "label" => "b",
            "rings" => [ [ [ 100.0, 0.0 ], [ 200.0, 0.0 ], [ 200.0, 50.0 ], [ 100.0, 50.0 ] ] ]
          }
        ],
        cut_segments: [
          [ [ 100.0, 0.0 ], [ 100.0, 50.0 ] ]
        ]
      )
    end

    it "[REQ-FIT-SPLIT-001] renders child paths and cut lines with visible classes" do
      svg = split_plan_preview_svg(orphan, css_class: "split-plan-preview__svg")

      expect(svg).to include('class="split-plan-preview__child"')
      expect(svg).to include('class="split-plan-preview__child split-plan-preview__child--alt"')
      expect(svg).to include('class="split-plan-preview__cut"')
      expect(svg).to include('class="split-plan-preview__mother"')
      expect(svg).to include('viewBox="0 0 ')
    end

    it "returns nil when no split proposal exists" do
      orphan_without_proposal = Nesting::OrphansPresenter::Orphan.new(
        piece_index: 0,
        piece_key: "0",
        reason: "oversized_for_sheet",
        rings: orphan.rings,
        width_mm: orphan.width_mm,
        height_mm: orphan.height_mm,
        offset_x_mm: 0.0,
        offset_y_mm: 0.0,
        resolution_state: "system_split",
        split_proposal: nil
      )

      expect(split_plan_preview_svg(orphan_without_proposal, css_class: "split-plan-preview__svg")).to be_nil
    end

    it "returns nil for non-draft, non-accepted proposals" do
      rejected_proposal = SplitProposal.new(
        status: :rejected,
        feasible: true,
        child_piece_geometries: proposal.child_piece_geometries,
        cut_segments: proposal.cut_segments
      )
      orphan_rejected = Nesting::OrphansPresenter::Orphan.new(
        piece_index: 0,
        piece_key: "0",
        reason: "oversized_for_sheet",
        rings: orphan.rings,
        width_mm: orphan.width_mm,
        height_mm: orphan.height_mm,
        offset_x_mm: 0.0,
        offset_y_mm: 0.0,
        resolution_state: "system_split",
        split_proposal: rejected_proposal
      )

      expect(split_plan_preview_svg(orphan_rejected, css_class: "split-plan-preview__svg")).to be_nil
    end

    it "returns nil when child geometries produce empty bounds" do
      empty_proposal = SplitProposal.new(
        status: :draft,
        feasible: true,
        child_piece_geometries: [],
        cut_segments: []
      )
      orphan_empty = Nesting::OrphansPresenter::Orphan.new(
        piece_index: 0,
        piece_key: "0",
        reason: "oversized_for_sheet",
        rings: [],
        width_mm: orphan.width_mm,
        height_mm: orphan.height_mm,
        offset_x_mm: 0.0,
        offset_y_mm: 0.0,
        resolution_state: "system_split",
        split_proposal: empty_proposal
      )

      expect(split_plan_preview_svg(orphan_empty, css_class: "split-plan-preview__svg")).to be_nil
    end
  end

  describe "#orphan_preview_svg [REQ-FIT-NEST-003]" do
    let(:orphan) do
      Nesting::OrphansPresenter::Orphan.new(
        piece_index: 0,
        piece_key: "0",
        reason: "oversized_for_sheet",
        rings: [ [ [ 0.0, 0.0 ], [ 50.0, 0.0 ], [ 50.0, 30.0 ], [ 0.0, 30.0 ] ] ],
        width_mm: 50.0,
        height_mm: 30.0,
        offset_x_mm: 0.0,
        offset_y_mm: 0.0,
        resolution_state: "manual",
        split_proposal: nil
      )
    end

    it "renders orphan preview paths and dimension labels" do
      svg = orphan_preview_svg(orphan, css_class: "orphan-preview__svg")

      expect(svg).to include('data-testid="orphan-preview-svg"')
      expect(orphan_preview_dimensions(orphan)).to include("50")
    end
  end
end

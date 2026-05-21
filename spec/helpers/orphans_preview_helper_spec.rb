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
  end
end

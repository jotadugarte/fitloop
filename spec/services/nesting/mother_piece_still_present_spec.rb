# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::MotherPieceStillPresent, "[REQ-FIT-SPLIT-001]" do
  it "returns false when the project has no DXF attachments" do
    project = create_project_for_spec!(title: "Mother missing dxf", bind_workspace: false)
    rings = [ [ [ 0, 0 ], [ 10, 0 ], [ 10, 10 ], [ 0, 10 ] ] ]

    expect(described_class.call(project: project, mother_rings: rings, layer_name: "PIECES")).to be(false)
  end

  it "yields no DXF paths when the project has no attachments" do
    project = create_project_for_spec!(title: "Mother blank paths", bind_workspace: false)
    service = described_class.new(project: project, mother_rings: [], layer_name: "PIECES")

    paths = service.send(:with_downloaded_dxf_paths) { |downloaded| downloaded }

    expect(paths).to eq([])
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe SourceDxfPreviewHelper, "[REQ-FIT-UI-002]" do
  include described_class

  PreviewStub = Struct.new(:offset_x_mm, :offset_y_mm, :view_height, keyword_init: true)
  PolylineStub = Struct.new(:points, :is_open, :internal_cut, keyword_init: true)

  let(:preview) { PreviewStub.new(offset_x_mm: 0.0, offset_y_mm: 0.0, view_height: 100.0) }

  it "closes exterior polygon paths with Z" do
    line = PolylineStub.new(
      points: [ [ 0.0, 0.0 ], [ 10.0, 0.0 ], [ 10.0, 20.0 ], [ 0.0, 20.0 ] ],
      is_open: false,
      internal_cut: false
    )

    expect(source_dxf_polyline_path(line, preview: preview)).to end_with("Z")
  end

  it "does not close open contours or internal cut segments" do
    open_line = PolylineStub.new(
      points: [ [ 0.0, 0.0 ], [ 10.0, 0.0 ] ],
      is_open: true,
      internal_cut: false
    )
    internal_line = PolylineStub.new(
      points: [ [ 0.0, 0.0 ], [ 10.0, 0.0 ] ],
      is_open: false,
      internal_cut: true
    )

    expect(source_dxf_polyline_path(open_line, preview: preview)).not_to end_with("Z")
    expect(source_dxf_polyline_path(internal_line, preview: preview)).not_to end_with("Z")
    expect(source_dxf_polyline_path([ [ 0.0, 0.0 ], [ 10.0, 0.0 ] ], preview: preview)).not_to end_with("Z")
  end

  it "does not append Z for a single-point closed polyline" do
    line = PolylineStub.new(points: [ [ 0.0, 0.0 ] ], is_open: false, internal_cut: false)

    expect(source_dxf_polyline_path(line, preview: preview)).not_to end_with("Z")
  end
end

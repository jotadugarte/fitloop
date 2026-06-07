# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::PieceKeyBuilder do
  let(:project) { create_project_for_spec!(title: "Piece key bench", bind_workspace: false) }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def attach_dxf!(filename: "panel-a.dxf")
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: filename,
      content_type: "application/dxf"
    )
    project.input_dxf.last
  end

  describe ".call [REQ-FIT-SPLIT-001]" do
    it "[REQ-FIT-SPLIT-001] builds a PieceKey from blob id and per-file piece index" do
      attachment = attach_dxf!

      key = described_class.call(attachment: attachment, piece_index: 7)

      expect(key).to be_a(Nesting::PieceKey)
      expect(key.to_s).to eq("#{attachment.blob_id}:piece-7")
    end

    it "[REQ-FIT-SPLIT-001] is stable across repeated calls" do
      attachment = attach_dxf!

      first = described_class.call(attachment: attachment, piece_index: 2)
      second = described_class.call(attachment: attachment, piece_index: 2)

      expect(first).to eq(second)
    end

    it "[REQ-FIT-SPLIT-001] differs when the source DXF blob or piece index changes" do
      first_attachment = attach_dxf!(filename: "first.dxf")
      second_attachment = attach_dxf!(filename: "second.dxf")

      same_file = described_class.call(attachment: first_attachment, piece_index: 0)
      other_file = described_class.call(attachment: second_attachment, piece_index: 0)
      other_index = described_class.call(attachment: first_attachment, piece_index: 1)

      expect(other_file).not_to eq(same_file)
      expect(other_index).not_to eq(same_file)
    end
  end

  describe ".from_geometry [REQ-FIT-SPLIT-001]" do
    let(:attachment) { attach_dxf! }
    let(:rings) do
      [
        [
          [ 0.0, 0.0 ],
          [ 120.0, 0.0 ],
          [ 120.0, 50.0 ],
          [ 0.0, 50.0 ]
        ]
      ]
    end

    it "[REQ-FIT-SPLIT-001] fingerprints geometry when piece index is unavailable" do
      first = described_class.from_geometry(
        attachment: attachment,
        layer_name: "CUT",
        rings: rings
      )
      second = described_class.from_geometry(
        attachment: attachment,
        layer_name: "CUT",
        rings: rings
      )

      expect(first).to be_a(Nesting::PieceKey)
      expect(first).to eq(second)
      expect(first.to_s).to start_with("#{attachment.blob_id}:fp-")
    end

    it "[REQ-FIT-SPLIT-001] changes the fingerprint when geometry changes" do
      shifted = described_class.from_geometry(
        attachment: attachment,
        layer_name: "CUT",
        rings: [
          [
            [ 10.0, 0.0 ],
            [ 130.0, 0.0 ],
            [ 130.0, 50.0 ],
            [ 10.0, 50.0 ]
          ]
        ]
      )
      baseline = described_class.from_geometry(
        attachment: attachment,
        layer_name: "CUT",
        rings: rings
      )

      expect(shifted).not_to eq(baseline)
    end
  end

  describe "validation branches [REQ-FIT-SPLIT-001]" do
    it "requires attachment and blob id" do
      builder = described_class.new

      expect { builder.build_from_index(attachment: nil, piece_index: 0) }
        .to raise_error(ArgumentError, /attachment is required/)

      attachment = instance_double(ActiveStorage::Attachment, blob_id: nil)
      expect { builder.build_from_index(attachment: attachment, piece_index: 0) }
        .to raise_error(ArgumentError, /attachment blob is required/)
    end

    it "rejects negative piece indexes and malformed ring points" do
      attachment = attach_dxf!

      expect { described_class.call(attachment: attachment, piece_index: -1) }
        .to raise_error(ArgumentError, /non-negative/)

      expect do
        described_class.from_geometry(
          attachment: attachment,
          layer_name: "CUT",
          rings: [ [ [ 1.0 ] ] ]
        )
      end.to raise_error(ArgumentError, /ring point must have x and y/)
    end
  end
end

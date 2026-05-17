# frozen_string_literal: true

module GoldenFixtures
  GOLDEN_DXF = Rails.root.join("spec/fixtures/golden/sample_piece.dxf").freeze

  def self.assert_present!
    raise "Missing golden DXF: #{GOLDEN_DXF}" unless GOLDEN_DXF.file?
  end
end

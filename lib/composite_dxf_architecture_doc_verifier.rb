# frozen_string_literal: true

# [REQ-FIT-DXF-002] [REQ-FIT-ARCH-001] Validates composite DXF ADR and CLI README.
class CompositeDxfArchitectureDocVerifier
  ADR_PATH = File.expand_path("../docs/core/ADRs/0003-composite-dxf-layers.md", __dir__)
  README_PATH = File.expand_path("../nesting_engine/README.md", __dir__)
  ROADMAP_PATH = File.expand_path("../docs/ROADMAP.md", __dir__)

  ADR_MARKERS = [
    "REQ-FIT-DXF-002",
    "CompositePiece",
    "DecorationEntity",
    "composite_extract",
    "primary_layer",
    "auxiliary_layers"
  ].freeze

  README_MARKERS = [
    "input_files",
    "primary_layer",
    "auxiliary_layers",
    "composite_extract",
    "REQ-FIT-DXF-002"
  ].freeze

  ROADMAP_MARKERS = [
    "v1.2",
    "REQ-FIT-DXF-002",
    "ADR-0003"
  ].freeze

  def self.verify!
    new.verify!
  end

  def verify!
    errors = []
    errors << "missing ADR: #{ADR_PATH}" unless File.file?(ADR_PATH)

    if File.file?(ADR_PATH)
      adr_content = File.read(ADR_PATH)
      ADR_MARKERS.each do |marker|
        errors << "ADR missing marker: #{marker}" unless adr_content.include?(marker)
      end
    end

    readme_content = File.read(README_PATH)
    README_MARKERS.each do |marker|
      errors << "README missing composite marker: #{marker}" unless readme_content.include?(marker)
    end

    roadmap_content = File.read(ROADMAP_PATH)
    ROADMAP_MARKERS.each do |marker|
      errors << "ROADMAP missing composite marker: #{marker}" unless roadmap_content.include?(marker)
    end

    raise CompositeDxfArchitectureDocError, errors.join("; ") if errors.any?

    true
  end
end

class CompositeDxfArchitectureDocError < StandardError; end

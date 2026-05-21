# frozen_string_literal: true

# [REQ-FIT-DXF-002] Validates composite DXF layer requirement detail in core docs.
class CompositeDxfSpecDocVerifier
  SPEC_PATH = File.expand_path("../docs/core/SPEC.md", __dir__)
  DATA_FLOW_PATH = File.expand_path("../docs/core/DATA_FLOW_MAP.md", __dir__)

  SPEC_TABLE_MARKER = "**REQ-FIT-DXF-002**"
  SPEC_DETAIL_HEADING = "### REQ-FIT-DXF-002 (detail)"
  DATA_FLOW_HEADING = "## 9. Composite DXF layers (W7)"

  SPEC_MARKERS = [
    "primary layer",
    "per file",
    "auxiliary",
    "CompositePiece",
    "DecorationEntity",
    "layer_role",
    "intersection",
    "insert point",
    "TEXT",
    "MTEXT",
    "INSERT",
    "original layer names",
    "nested.dxf",
    "partition_decorations",
    "REQ-FIT-SPLIT-001",
    "excluded_piece_keys",
    "derived_pieces",
    "decorations"
  ].freeze

  DATA_FLOW_MARKERS = [
    "composite_extract",
    "primary_layer",
    "auxiliary_layers",
    "load_composite_pieces",
    "partition_decorations",
    "decoration_transform",
    "REQ-FIT-SPLIT-001",
    "derived_pieces",
    "decorations_json"
  ].freeze

  def self.verify!
    new.verify!
  end

  def verify!
    errors = []
    spec_content = File.read(SPEC_PATH)
    data_flow_content = File.read(DATA_FLOW_PATH)

    errors << "missing SPEC table row: #{SPEC_TABLE_MARKER}" unless spec_content.include?(SPEC_TABLE_MARKER)
    errors << "missing SPEC detail heading: #{SPEC_DETAIL_HEADING}" unless spec_content.include?(SPEC_DETAIL_HEADING)
    errors << "missing DATA_FLOW section: #{DATA_FLOW_HEADING}" unless data_flow_content.include?(DATA_FLOW_HEADING)

    detail_section = extract_section(spec_content, SPEC_DETAIL_HEADING)
    if detail_section.nil?
      errors << "REQ-FIT-DXF-002 detail section is empty"
    else
      SPEC_MARKERS.each do |marker|
        errors << "SPEC missing composite marker: #{marker}" unless detail_section.include?(marker)
      end
    end

    flow_section = extract_section(data_flow_content, DATA_FLOW_HEADING)
    if flow_section.nil?
      errors << "composite data flow section is empty"
    else
      DATA_FLOW_MARKERS.each do |marker|
        errors << "DATA_FLOW_MAP missing composite marker: #{marker}" unless flow_section.include?(marker)
      end
    end

    raise CompositeDxfSpecDocError, errors.join("; ") if errors.any?

    true
  end

  private

  def extract_section(content, heading)
    start = content.index(heading)
    return nil unless start

    rest = content[(start + heading.length)..]
    next_heading = rest&.index(/\n### |\n## /)
    body = next_heading ? rest[0...next_heading] : rest
    body&.strip
  end
end

class CompositeDxfSpecDocError < StandardError; end

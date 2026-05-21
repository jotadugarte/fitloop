# frozen_string_literal: true

# [REQ-FIT-SPLIT-001] Validates auto-split requirement detail in core docs.
class SplitSpecDocVerifier
  SPEC_PATH = File.expand_path("../docs/core/SPEC.md", __dir__)
  DATA_FLOW_PATH = File.expand_path("../docs/core/DATA_FLOW_MAP.md", __dir__)

  SPEC_DETAIL_HEADING = "### REQ-FIT-SPLIT-001 (detail)"
  DATA_FLOW_HEADING = "## 8. Auto-split workflow (W6)"

  SPEC_MARKERS = [
    "opt-in",
    "pending",
    "system_split",
    "manual",
    "resolved",
    "ephemeral",
    "PieceKey",
    "plan_splits",
    "split_preview.json",
    "excluded_piece_keys",
    "derived_pieces",
    "split_not_feasible",
    "preview",
    "OrphanResolution",
    "SplitProposal",
    "DerivedPiece"
  ].freeze

  DATA_FLOW_MARKERS = [
    "OrphanResolution",
    "plan_splits",
    "split_preview.json",
    "excluded_piece_keys",
    "derived_pieces",
    "Nesting::SplitPlanJob",
    "Anidar con piezas actualizadas"
  ].freeze

  def self.verify!
    new.verify!
  end

  def verify!
    errors = []
    spec_content = File.read(SPEC_PATH)
    data_flow_content = File.read(DATA_FLOW_PATH)

    errors << "missing SPEC detail heading: #{SPEC_DETAIL_HEADING}" unless spec_content.include?(SPEC_DETAIL_HEADING)
    errors << "missing DATA_FLOW section: #{DATA_FLOW_HEADING}" unless data_flow_content.include?(DATA_FLOW_HEADING)

    detail_section = extract_section(spec_content, SPEC_DETAIL_HEADING)
    if detail_section.nil?
      errors << "REQ-FIT-SPLIT-001 detail section is empty"
    else
      SPEC_MARKERS.each do |marker|
        errors << "SPEC missing split marker: #{marker}" unless detail_section.include?(marker)
      end
    end

    flow_section = extract_section(data_flow_content, DATA_FLOW_HEADING)
    if flow_section.nil?
      errors << "auto-split data flow section is empty"
    else
      DATA_FLOW_MARKERS.each do |marker|
        errors << "DATA_FLOW_MAP missing split marker: #{marker}" unless flow_section.include?(marker)
      end
    end

    raise SplitSpecDocError, errors.join("; ") if errors.any?

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

class SplitSpecDocError < StandardError; end

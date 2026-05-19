# frozen_string_literal: true

module SheetStocks
  # [REQ-FIT-SPLIT-001] Drop draft split previews when sheet inventory changes (G32).
  class InvalidateSplitPreviews
    def self.call(project)
      SplitProposal
        .joins(:orphan_resolution)
        .where(orphan_resolutions: { project_id: project.id }, status: :draft)
        .delete_all
    end
  end
end

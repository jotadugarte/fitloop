# frozen_string_literal: true

module SheetStocks
  # [REQ-FIT-UI-001] Drop sheet stocks omitted from a nested-attributes POST (form is source of truth).
  class SyncInventory
    def self.call(project:, sheet_stocks_attributes:)
      new(project: project, sheet_stocks_attributes: sheet_stocks_attributes).call
    end

    def initialize(project:, sheet_stocks_attributes:)
      @project = project
      @attributes = sheet_stocks_attributes || {}
    end

    def call
      stale = @project.sheet_stocks.where.not(id: kept_sheet_stock_ids)
      removed = stale.exists?
      stale.destroy_all
      if removed
        InvalidateNestingOutputs.call(@project)
        InvalidateSplitPreviews.call(@project)
      end
      removed
    end

    private

    def kept_sheet_stock_ids
      @attributes.each_value.filter_map do |attrs|
        next unless attrs.is_a?(Hash)

        id = attrs[:id] || attrs["id"]
        id.presence&.to_i
      end
    end
  end
end

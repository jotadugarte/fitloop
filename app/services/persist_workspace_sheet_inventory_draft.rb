# frozen_string_literal: true

# [REQ-FIT-UI-005] Save in-progress sheet inventory before locale redirect (setup / workshop).
class PersistWorkspaceSheetInventoryDraft
  COMPOSER_SESSION_KEY = :workspace_composer_draft

  def self.call(session:, params:, tab_id: nil)
    new(session: session, params: params, tab_id: tab_id).call
  end

  def initialize(session:, params:, tab_id: nil)
    @session = session
    @params = params
    @tab_id = tab_id
  end

  def call
    project = Workspace.any_bound_project(@session, prefer_tab_id: @tab_id)
    return false unless project
    return false unless @params[:project].present?

    sheet_stocks_attributes = extract_sheet_stocks_attributes
    return false if sheet_stocks_attributes.blank?
    return false if omitting_persisted_stock_ids?(project, sheet_stocks_attributes)

    SheetStocks::SyncInventory.call(
      project: project,
      sheet_stocks_attributes: sheet_stocks_attributes
    )
    project.assign_attributes(sheet_stocks_attributes: sheet_stocks_attributes)
    SheetStocks::NormalizeConsumptionOrder.call(project)
    saved = project.save
    stash_composer_draft! if saved
    saved
  end

  private

  def extract_sheet_stocks_attributes
    raw = @params.require(:project).permit(
      sheet_stocks_attributes: %i[id width_mm height_mm quantity sort_order _destroy]
    )["sheet_stocks_attributes"]
    return nil if raw.blank?

    normalize_sheet_quantities!(raw)
    raw
  end

  def normalize_sheet_quantities!(sheet_stocks_attributes)
    sheet_stocks_attributes.each_value do |attrs|
      next unless attrs.is_a?(Hash)

      quantity = attrs[:quantity].presence || attrs["quantity"].presence
      attrs[:quantity] = quantity.present? ? quantity.to_i : nil
    end
  end

  def omitting_persisted_stock_ids?(project, sheet_stocks_attributes)
    return false unless project.sheet_stocks.exists?

    kept_sheet_stock_ids(sheet_stocks_attributes).empty?
  end

  def kept_sheet_stock_ids(sheet_stocks_attributes)
    sheet_stocks_attributes.each_value.filter_map do |attrs|
      next unless attrs.is_a?(Hash)

      id = attrs[:id] || attrs["id"]
      id.presence&.to_i
    end
  end

  def stash_composer_draft!
    draft = @params.fetch(:composer_draft, {}).permit(:width_mm, :height_mm, :quantity).to_h
    return if draft.values.all?(&:blank?)

    @session[COMPOSER_SESSION_KEY] = draft
  end
end

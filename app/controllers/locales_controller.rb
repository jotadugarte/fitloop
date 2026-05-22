# frozen_string_literal: true

# [REQ-FIT-UI-005] Persist user locale choice and return to the previous page.
class LocalesController < ApplicationController
  def update
    locale = params.require(:locale).to_sym
    unless I18n.available_locales.include?(locale)
      redirect_back fallback_location: root_path, status: :see_other
      return
    end

    PersistWorkspaceSheetInventoryDraft.call(
      session: session,
      params: params,
      tab_id: workspace_tab_id
    )
    persist_locale!(locale)
    redirect_back fallback_location: root_path, status: :see_other
  end
end

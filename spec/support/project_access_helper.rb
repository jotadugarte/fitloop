# frozen_string_literal: true

module ProjectAccessHelper
  def unlock_project_for_spec!(project, pin:)
    if respond_to?(:visit)
      visit project_path(project)
      fill_in I18n.t("projects.access.pin_label"), with: pin
      click_button I18n.t("projects.access.unlock")
    else
      post verify_pin_project_path(project), params: { pin: pin }
    end
  end
end

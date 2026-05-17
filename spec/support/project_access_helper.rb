# frozen_string_literal: true

module ProjectAccessHelper
  def unlock_project_for_spec!(project, pin:)
    post verify_pin_project_path(project), params: { pin: pin }
  end
end

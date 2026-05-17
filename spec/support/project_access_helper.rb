# frozen_string_literal: true

module ProjectAccessHelper
  def grant_project_access!(project, pin:)
    post verify_pin_project_path(project), params: { pin: pin }
  end
end

RSpec.configure do |config|
  config.include ProjectAccessHelper, type: :request
  config.include ProjectAccessHelper, type: :system
end

# frozen_string_literal: true

# Binds the ephemeral project to the current session (replaces legacy PIN unlock).
module ProjectAccessHelper
  def unlock_project_for_spec!(project, pin: nil)
    _ = pin
    raise ArgumentError, "unlock_project_for_spec! requires an ephemeral project" unless project.ephemeral?

    if respond_to?(:session) && session
      session[Workspace::SESSION_KEY] = project.id
    end

    return unless respond_to?(:visit)

    visit project_path(project)
  end
end

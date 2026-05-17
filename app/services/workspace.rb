# frozen_string_literal: true

# Ephemeral in-browser workspace: one project per session, discarded when the user leaves.
class Workspace
  SESSION_KEY = :workspace_project_id

  class << self
    def find(session)
      project_id = session[SESSION_KEY]
      return nil if project_id.blank?

      Project.ephemeral.find_by(id: project_id)
    end

    def find_or_create!(session)
      project = find(session)
      session.delete(SESSION_KEY) if project.nil? && session[SESSION_KEY].present?
      find(session) || create!(session)
    end

    def resolve!(session, project_id)
      project_id = project_id.to_i
      if session[SESSION_KEY].to_i == project_id
        project = find(session)
        return project if project

        raise ActiveRecord::RecordNotFound, "Workspace project #{project_id} was discarded"
      end

      Project.find(project_id)
    end

    def discard!(session)
      project = find(session)
      project&.destroy
      session.delete(SESSION_KEY)
    end

    def bind!(session, project)
      session[SESSION_KEY] = project.id
    end

    def create!(session)
      project = Project.create!(
        ephemeral: true,
        title: I18n.t("workspace.default_title"),
        status: :draft
      )
      bind!(session, project)
      project
    end

    def reset!(session)
      discard!(session)
      create!(session)
    end
  end
end

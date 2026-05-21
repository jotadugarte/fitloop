# frozen_string_literal: true

require "fileutils"

# Ephemeral in-browser workspace: one project per session, discarded when the user leaves.
class Workspace
  SESSION_KEY = :workspace_project_id
  NESTING_RUNS_DIR = Rails.root.join("tmp/nesting_runs").freeze

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
      unless session[SESSION_KEY].to_i == project_id
        raise ActiveRecord::RecordNotFound,
              "Ephemeral project #{project_id} is not bound to this session"
      end

      project = find(session)
      raise ActiveRecord::RecordNotFound, "Workspace project #{project_id} was discarded" unless project

      project
    end

    def discard!(session)
      project = find(session)
      cancel_active_nesting!(project) if project
      project&.destroy
      session.delete(SESSION_KEY)
    end

    # Remove abandoned ephemeral projects (browser closed without visiting home).
    def purge_all_ephemeral!
      destroyed = 0
      Project.ephemeral.find_each do |project|
        project.destroy!
        destroyed += 1
      end
      purge_nesting_run_dirs!
      destroyed
    end

    # Dev/maintenance: wipe all projects, sheet stocks, nesting runs, and temp dirs.
    def purge_all!
      projects_count = Project.count
      Project.destroy_all
      nesting_dirs = purge_nesting_run_dirs!
      blobs_count = purge_orphan_storage_blobs!
      { projects: projects_count, nesting_dirs: nesting_dirs, blobs: blobs_count }
    end

    def purge_nesting_run_dirs!
      return 0 unless NESTING_RUNS_DIR.directory?

      count = NESTING_RUNS_DIR.children.count
      FileUtils.rm_rf(NESTING_RUNS_DIR)
      FileUtils.mkdir_p(NESTING_RUNS_DIR)
      count
    end

    def purge_orphan_storage_blobs!
      orphaned = ActiveStorage::Blob.left_joins(:attachments).where(active_storage_attachments: { id: nil })
      count = orphaned.count
      orphaned.find_each(&:purge)
      count
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

    private

    def cancel_active_nesting!(project)
      project.nesting_runs.where(status: "processing").find_each do |run|
        run.update!(cancel_requested_at: Time.current) if run.cancel_requested_at.blank?
        Nesting::ApplyCancel.call(nesting_run: run)
      end
    end
  end
end

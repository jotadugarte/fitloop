# frozen_string_literal: true

require "fileutils"

# Ephemeral in-browser workspace: projects per browser tab, discarded on leave or tab-close TTL.
class Workspace
  extend TabLeave

  SESSION_KEY = :workspace_project_id
  WORKSPACES_KEY = :workspaces
  DEFAULT_TAB_ID = "__default__"
  NESTING_RUNS_DIR = Rails.root.join("tmp/nesting_runs").freeze

  class << self
    def bound?(session)
      session[SESSION_KEY].present? || workspaces_hash(session).present?
    end

    def active_project?(session)
      tab_ids(session).any? { |tab_id| find(session, tab_id: tab_id).present? }
    end

    def find(session, tab_id: nil)
      tid = normalize_tab_id(tab_id)
      project_id = bound_project_id(session, tab_id: tid)
      return nil if project_id.blank?

      project = Project.ephemeral.find_by(id: project_id)
      clear_stale_bind!(session, tid) if project.nil?
      project
    end

    # First bound ephemeral project in this session (any tab). Used when the browser tab id drifted.
    def any_bound_project(session, prefer_tab_id: nil)
      if prefer_tab_id.present?
        project = find(session, tab_id: prefer_tab_id)
        return project if project
      end

      workspaces_hash(session).each_key do |tid|
        project = find(session, tab_id: tid)
        return project if project
      end

      find(session, tab_id: DEFAULT_TAB_ID)
    end

    def bound_to_project?(session, project)
      project_id = project.is_a?(Project) ? project.id : Integer(project)
      workspaces_hash(session).values.any? { |bound_id| bound_id.to_i == project_id } ||
        session[SESSION_KEY].to_i == project_id
    end

    def tab_id_for_project(session, project_id)
      workspaces_hash(session).find { |_tab, pid| pid.to_i == project_id.to_i }&.first
    end

    def find_or_create!(session, tab_id: nil, request: nil)
      tid = normalize_tab_id(tab_id)
      find(session, tab_id: tid) || create!(session, tab_id: tid, request: request)
    end

    def resolve!(session, project_id, tab_id: nil)
      project_id = project_id.to_i
      tid = normalize_tab_id(tab_id)
      unless bound_project_id(session, tab_id: tid).to_i == project_id
        raise ActiveRecord::RecordNotFound,
              "Ephemeral project #{project_id} is not bound to this session"
      end

      project = find(session, tab_id: tid)
      raise ActiveRecord::RecordNotFound, "Workspace project #{project_id} was discarded" unless project

      project
    end

    def discard!(session, tab_id: nil, request: nil)
      if tab_id.present?
        discard_tab!(session, normalize_tab_id(tab_id), request: request)
      else
        tab_ids(session).each { |tid| discard_tab!(session, tid, request: request) }
        session.delete(SESSION_KEY)
        session.delete(WORKSPACES_KEY)
      end
    end

    def purge_all_ephemeral!
      destroyed = 0
      Project.ephemeral.find_each do |project|
        project.destroy!
        destroyed += 1
      end
      purge_nesting_run_dirs!
      destroyed
    end

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

    def bind!(session, project, tab_id: nil)
      tid = normalize_tab_id(tab_id)
      hash = workspaces_hash(session)
      hash[tid] = project.id
      session[WORKSPACES_KEY] = hash
      sync_legacy_session_key!(session)
    end

    def create!(session, tab_id: nil, request: nil)
      project = Project.create!(
        ephemeral: true,
        title: I18n.t("workspace.default_title"),
        status: :draft,
        last_activity_at: Time.current
      )
      bind!(session, project, tab_id: tab_id)

      Analytics::TrackEvent.call(
        "workspace_started",
        user_id: request&.env&.[]("warden")&.user&.id,
        anonymous_session_key: session[:anonymous_session_key],
        tab_id: normalize_tab_id(tab_id),
        project_id: project.id,
        ip: request&.remote_ip,
        user_agent: request&.user_agent,
        country_code: Analytics::ResolveCountry.call(request),
        locale: I18n.locale.to_s
      )

      project
    end

    def reset!(session, tab_id: nil, request: nil)
      discard!(session, tab_id: tab_id, request: request)
      create!(session, tab_id: tab_id, request: request)
    end

    private

    def normalize_tab_id(tab_id)
      tab_id.presence || DEFAULT_TAB_ID
    end

    def workspaces_hash(session)
      session[WORKSPACES_KEY] = (session[WORKSPACES_KEY] || {}).stringify_keys
    end

    def tab_ids(session)
      ids = workspaces_hash(session).keys
      return ids if ids.present?

      session[SESSION_KEY].present? ? [DEFAULT_TAB_ID] : []
    end

    def bound_project_id(session, tab_id:)
      tid = normalize_tab_id(tab_id)
      workspaces_hash(session)[tid].presence || legacy_bound_project_id(session, tab_id: tid)
    end

    def legacy_bound_project_id(session, tab_id:)
      return nil unless tab_id == DEFAULT_TAB_ID

      session[SESSION_KEY]
    end

    def sync_legacy_session_key!(session)
      ids = workspaces_hash(session).values
      if ids.empty?
        session.delete(SESSION_KEY)
      elsif tab_ids(session).include?(DEFAULT_TAB_ID)
        session[SESSION_KEY] = workspaces_hash(session)[DEFAULT_TAB_ID]
      else
        session.delete(SESSION_KEY)
      end
    end

    def clear_stale_bind!(session, tab_id)
      workspaces_hash(session).delete(tab_id)
      session[WORKSPACES_KEY] = workspaces_hash(session)
      sync_legacy_session_key!(session)
    end

    def discard_tab!(session, tab_id, request: nil)
      project = find(session, tab_id: tab_id)
      cancel_active_nesting!(project) if project
      if project
        Analytics::TrackEvent.call(
          "project_discarded",
          user_id: request&.env&.[]("warden")&.user&.id,
          anonymous_session_key: session[:anonymous_session_key],
          tab_id: tab_id,
          project_id: project.id,
          ip: request&.remote_ip,
          user_agent: request&.user_agent,
          country_code: Analytics::ResolveCountry.call(request),
          locale: I18n.locale.to_s,
          properties: project.metadata_snapshot
        )
        project.destroy
      end
      workspaces_hash(session).delete(tab_id)
      session[WORKSPACES_KEY] = workspaces_hash(session)
      sync_legacy_session_key!(session)
    end

    def expire_project!(session, project, tab_id:, request: nil)
      cancel_active_nesting!(project)
      Analytics::TrackEvent.call(
        "project_discarded",
        user_id: request&.env&.[]("warden")&.user&.id,
        anonymous_session_key: session[:anonymous_session_key],
        tab_id: tab_id,
        project_id: project.id,
        ip: request&.remote_ip,
        user_agent: request&.user_agent,
        country_code: Analytics::ResolveCountry.call(request),
        locale: I18n.locale.to_s,
        properties: project.metadata_snapshot
      )
      project.destroy!
      workspaces_hash(session).delete(tab_id)
      session[WORKSPACES_KEY] = workspaces_hash(session)
      sync_legacy_session_key!(session)
    end

    def cancel_active_nesting!(project)
      project.nesting_runs.where(status: "processing").find_each do |run|
        run.update!(cancel_requested_at: Time.current) if run.cancel_requested_at.blank?
        Nesting::ApplyCancel.call(nesting_run: run)
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orphan resolutions", type: :request do
  describe "PATCH /projects/:project_id/orphan_resolutions/:piece_key [REQ-FIT-SPLIT-001]" do
    let(:project) { start_ephemeral_workspace! }
    let(:piece_key) { "0" }
    let(:base_params) do
      {
        orphan_resolution: {
          resolution_state: resolution_state,
          reason: "oversized_for_sheet"
        }
      }
    end

    context "when resolution_state is system_split" do
      let(:resolution_state) { "system_split" }

      it "[REQ-FIT-SPLIT-001] upserts OrphanResolution and redirects to project show" do
        patch project_orphan_resolution_path(project, piece_key), params: base_params

        expect(response).to redirect_to(project_path(project))
        resolution = project.orphan_resolutions.find_by!(piece_key: piece_key)
        expect(resolution.resolution_state).to eq("system_split")
        expect(resolution.reason).to eq("oversized_for_sheet")
      end

      it "[REQ-FIT-SPLIT-001] enqueues split planning when resolution_state is system_split" do
        ActiveJob::Base.queue_adapter = :test

        expect {
          patch project_orphan_resolution_path(project, piece_key), params: base_params
        }.to have_enqueued_job(Nesting::SplitPlanJob)
      end

      it "[REQ-FIT-SPLIT-001] appends a session_workflow_log event" do
        patch project_orphan_resolution_path(project, piece_key), params: base_params

        project.reload
        event = project.session_workflow_log.last
        expect(event).to include(
          "event" => "orphan_resolution_updated",
          "piece_key" => piece_key,
          "resolution_state" => "system_split"
        )
      end
    end

    context "when resolution_state is manual" do
      let(:resolution_state) { "manual" }

      it "[REQ-FIT-SPLIT-001] stores manual resolution state" do
        patch project_orphan_resolution_path(project, piece_key), params: base_params

        resolution = project.orphan_resolutions.find_by!(piece_key: piece_key)
        expect(resolution.resolution_state).to eq("manual")
      end
    end

    context "when resolution_state is pending" do
      let(:resolution_state) { "pending" }

      it "[REQ-FIT-SPLIT-001] stores pending resolution state" do
        OrphanResolution.create!(
          project: project,
          piece_key: piece_key,
          reason: "oversized_for_sheet",
          resolution_state: :system_split
        )

        patch project_orphan_resolution_path(project, piece_key), params: base_params

        expect(project.orphan_resolutions.find_by!(piece_key: piece_key).resolution_state).to eq("pending")
      end
    end

    it "[REQ-FIT-SPLIT-001] forbids updates on non-ephemeral projects" do
      saved = Project.create!(
        ephemeral: false,
        title: "Saved project",
        sheet_stocks_attributes: { "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 } }
      )
      allow_any_instance_of(OrphanResolutionsController).to receive(:set_workspace_project) do |controller|
        controller.instance_variable_set(:@project, saved)
      end

      patch project_orphan_resolution_path(saved, piece_key),
            params: {
              orphan_resolution: {
                resolution_state: "system_split",
                reason: "oversized_for_sheet"
              }
            }

      expect(response).to have_http_status(:forbidden)
    end

    it "[REQ-FIT-SPLIT-001] requires an active ephemeral workspace session" do
      patch project_orphan_resolution_path(project, piece_key),
            params: {
              orphan_resolution: {
                resolution_state: "system_split",
                reason: "oversized_for_sheet"
              }
            }

      get root_path
      expired_id = project.id

      patch project_orphan_resolution_path(expired_id, piece_key),
            params: {
              orphan_resolution: {
                resolution_state: "manual",
                reason: "oversized_for_sheet"
              }
            }

      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
    end
  end
end

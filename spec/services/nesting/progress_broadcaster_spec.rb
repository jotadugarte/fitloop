# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ProgressBroadcaster do
  let(:project) { create_project_for_spec!(title: "Broadcast bench", pin: "998877") }

  describe ".call [REQ-FIT-JOB-001]" do
    it "broadcasts nesting progress and, when not processing, actions and preview" do
      allow(project).to receive(:processing?).and_return(false)
      allow(project).to receive(:broadcast_replace_to)
      preview = instance_double(Nesting::PreviewPresenter)
      allow(Nesting::PreviewPresenter).to receive(:for).with(project).and_return(preview)

      described_class.call(project: project, eta_overrun: true, time_limit_notice: false)

      expect(project).to have_received(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :nesting_progress),
        partial: "projects/nesting_progress",
        locals: {
          project: project,
          eta_overrun: true,
          time_limit_notice: false
        }
      )
      expect(project).to have_received(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :show_actions),
        partial: "projects/show_actions",
        locals: { project: project }
      )
      expect(project).to have_received(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :nesting_preview),
        partial: "projects/nesting_preview",
        locals: { project: project, preview: preview }
      )
    end

    it "broadcasts only nesting progress while processing" do
      allow(project).to receive(:processing?).and_return(true)
      allow(project).to receive(:broadcast_replace_to)

      described_class.call(project: project, eta_overrun: false, time_limit_notice: false)

      expect(project).to have_received(:broadcast_replace_to).once
    end
  end
end

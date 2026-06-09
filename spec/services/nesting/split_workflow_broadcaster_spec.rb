# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::SplitWorkflowBroadcaster, "[REQ-FIT-SPLIT-001]" do
  let(:project) { create_project_for_spec!(title: "Split broadcast") }

  describe ".call" do
    it "renders show_actions without Warden (Turbo broadcast context) [REQ-FIT-SPLIT-001]" do
      expect do
        ApplicationController.render(
          partial: "projects/show_actions",
          locals: { project: project }
        )
      end.not_to raise_error
    end

    it "broadcasts orphan frame and show_actions [REQ-FIT-SPLIT-001]" do
      allow(project).to receive(:broadcast_replace_to)
      orphans = instance_double(Nesting::OrphansPresenter)
      allow(Nesting::OrphansPresenter).to receive(:for).with(project).and_return(orphans)

      described_class.call(project: project)

      expect(project).to have_received(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :nesting_orphans),
        partial: "projects/nesting_orphans_frame",
        locals: { project: project, orphans: orphans }
      )
      expect(project).to have_received(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :show_actions),
        partial: "projects/show_actions",
        locals: { project: project }
      )
    end
  end
end

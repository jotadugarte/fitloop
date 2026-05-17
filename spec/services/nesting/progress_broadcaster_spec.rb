# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ProgressBroadcaster do
  let(:project) { create_project_for_spec!(title: "Broadcast bench", pin: "998877") }

  describe ".call [REQ-FIT-JOB-001]" do
    it "broadcasts a turbo stream replace for nesting progress" do
      expect(project).to receive(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :nesting_progress),
        partial: "projects/nesting_progress",
        locals: {
          project: project,
          eta_overrun: true,
          time_limit_notice: false
        }
      )

      described_class.call(project: project, eta_overrun: true, time_limit_notice: false)
    end
  end
end

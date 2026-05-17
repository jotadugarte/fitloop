# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe Nesting::ProgressBroadcaster do
  include Turbo::Broadcastable::TestHelper

  let(:project) { Project.create!(title: "Broadcast bench", pin: "998877") }

  describe ".call [REQ-FIT-JOB-001]" do
    it "broadcasts a turbo stream replace for nesting progress" do
      assert_turbo_stream_broadcasts project do
        described_class.call(project: project, eta_overrun: true, time_limit_notice: false)
      end
    end
  end
end

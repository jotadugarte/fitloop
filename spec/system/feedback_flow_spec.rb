# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Feedback flow", "[REQ-FIT-OPS-001]", type: :system do
  around do |example|
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  it "shows the FAB, submits feedback from the dialog form, and displays confirmation" do
    visit root_path

    expect(page).to have_css("[data-testid='feedback-fab']")

    within("[data-testid='feedback-dialog']", visible: :all) do
      select I18n.t("feedback.types.suggestion"), from: "feedback_feedback_type", visible: :all
      fill_in "feedback_email", with: "visitor@example.com", visible: :all
      fill_in "feedback_message", with: "Me encantaría ver más plantillas.", visible: :all
      click_button I18n.t("feedback.submit"), visible: :all
    end

    expect(page).to have_css("[data-testid='flash-notice']")
    expect(Feedback.find_by(email: "visitor@example.com")).to be_present
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nesting phase i18n labels [REQ-FIT-UI-003]" do
  PHASE_KEYS = %w[
    queued
    preparing
    starting
    extracting
    fill
    optimizing
    consolidating
    refining
    writing_outputs
  ].freeze

  %i[en es].each do |locale|
    context "when locale is #{locale}" do
      around do |example|
        I18n.with_locale(locale) { example.run }
      end

      it "defines all nesting.phase.* keys used by the progress UX" do
        PHASE_KEYS.each do |phase_key|
          label = I18n.t("nesting.phase.#{phase_key}")
          expect(label).to be_present
          expect(label).not_to start_with("translation missing")
        end
      end

      it "matches ProgressSnapshot phase i18n keys" do
        Nesting::ProgressSnapshot::PHASE_I18N_KEYS.each_value do |i18n_key|
          label = I18n.t(i18n_key)
          expect(label).to be_present
        end
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::LocalizedProgressMessage, "[REQ-FIT-UI-005]" do
  let(:project) do
    create_project_for_spec!(
      title: "Progress message bench",
      status: :completed,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
  end

  it "renders completed copy in the active locale even when DB stores another locale [REQ-FIT-UI-005]" do
    project.update!(progress_message: I18n.t("nesting.completed", locale: :es_panic))

    I18n.with_locale(:en) do
      expect(described_class.for(project)).to eq(I18n.t("nesting.completed", locale: :en))
    end

    I18n.with_locale(:es_panic) do
      expect(described_class.for(project)).to eq(I18n.t("nesting.completed", locale: :es_panic))
    end
  end

  it "returns empty text for blank progress on in-flight projects [REQ-FIT-UI-005]" do
    project.update!(status: :processing, progress_message: "")

    expect(described_class.for(project)).to eq("")
  end

  it "translates stored i18n keys during processing [REQ-FIT-UI-005]" do
    project.update!(status: :processing, progress_message: "nesting.phase.fill")

    I18n.with_locale(:es) do
      expect(described_class.for(project)).to eq(I18n.t("nesting.phase.fill", locale: :es))
    end
  end

  it "maps failed runs to cancelled or missing-input terminal copy [REQ-FIT-UI-005]" do
    project.update!(status: :failed, progress_message: "nesting.cancelled")

    expect(described_class.for(project)).to eq(I18n.t("nesting.cancelled"))

    project.update!(progress_message: "nesting.input_file_missing")
    expect(described_class.for(project)).to eq(I18n.t("nesting.input_file_missing"))
  end

  it "detects cancelled and missing-input messages from legacy locale text [REQ-FIT-UI-005]" do
    project.update!(status: :failed, progress_message: I18n.t("nesting.cancelled", locale: :es))

    expect(described_class.for(project)).to eq(I18n.t("nesting.cancelled"))

    project.update!(progress_message: I18n.t("nesting.input_file_missing", locale: :es))
    expect(described_class.for(project)).to eq(I18n.t("nesting.input_file_missing"))
  end

  it "returns false when locale matching receives blank text [REQ-FIT-UI-005]" do
    message = described_class.new(project)

    expect(message.send(:matches_any_locale?, "nesting.completed", "")).to be(false)
  end

  it "detects time limit notice from legacy translated text [REQ-FIT-UI-005]" do
    project.update!(
      status: :partial,
      progress_message: I18n.t("nesting.time_limit_notice", locale: :es_panic)
    )

    expect(described_class.time_limit_notice?(project)).to be(true)
  end
end

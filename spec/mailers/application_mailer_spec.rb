# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationMailer, type: :mailer do
  it "has default from address" do
    expect(described_class.default[:from]).to eq("from@example.com")
  end
end

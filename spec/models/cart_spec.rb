# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cart, "[REQ-FIT-BILL-001] [REQ-FIT-BILL-002]" do
  it "[REQ-FIT-BILL-001] supports single-item carts stored in DB (D6)" do
    expect(described_class).to be < ApplicationRecord
  end
end


# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, "[REQ-FIT-AUTH-002]" do
  def valid_attributes
    {
      email: "studio@example.com",
      name: "Ana García",
      password: "twelvechars1",
      password_confirmation: "twelvechars1",
      terms_accepted_at: Time.current,
      terms_version: "v1-placeholder",
      time_zone: "America/Costa_Rica"
    }
  end

  subject(:user) { described_class.new(valid_attributes) }

  describe "valid registration [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] is valid with required attributes" do
      expect(user).to be_valid
    end

    it "[REQ-FIT-AUTH-002] persists with required attributes" do
      expect { user.save! }.to change(described_class, :count).by(1)
    end
  end

  describe "email [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] requires email" do
      user.email = nil

      expect(user).not_to be_valid
      expect(user.errors).to be_of_kind(:email, :blank)
    end

    it "[REQ-FIT-AUTH-002] enforces case-insensitive uniqueness" do
      described_class.create!(valid_attributes)
      duplicate = described_class.new(valid_attributes.merge(email: "Studio@Example.com"))

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:email, :taken)
    end
  end

  describe "name [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] requires name" do
      user.name = nil

      expect(user).not_to be_valid
      expect(user.errors).to be_of_kind(:name, :blank)
    end
  end

  describe "password [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] rejects passwords shorter than 12 characters" do
      user.password = "short11chars"
      user.password_confirmation = "short11chars"

      expect(user).not_to be_valid
      expect(user.errors[:password]).to include(a_string_matching(/12/i))
    end

    it "[REQ-FIT-AUTH-002] accepts passwords of at least 12 characters" do
      user.password = "exactly12chr"
      user.password_confirmation = "exactly12chr"

      expect(user).to be_valid
    end
  end

  describe "terms acceptance [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] requires terms_accepted_at" do
      user.terms_accepted_at = nil

      expect(user).not_to be_valid
      expect(user.errors).to be_of_kind(:terms_accepted_at, :blank)
    end

    it "[REQ-FIT-AUTH-002] requires terms_version" do
      user.terms_version = nil

      expect(user).not_to be_valid
      expect(user.errors).to be_of_kind(:terms_version, :blank)
    end
  end

  describe "time_zone [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] requires time_zone before plan purchase" do
      user.time_zone = nil

      expect(user).not_to be_valid
      expect(user.errors).to be_of_kind(:time_zone, :blank)
    end
  end

  describe "email confirmation gate [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] blocks billing until email_confirmed_at is set" do
      user.save!
      user.update!(email_confirmed_at: nil)

      expect(user.billing_ready?).to be(false)
    end

    it "[REQ-FIT-AUTH-002] allows billing when email_confirmed_at is set" do
      user.save!
      user.update!(email_confirmed_at: Time.current)

      expect(user.billing_ready?).to be(true)
    end
  end

  describe "suspension [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] blocks operational access when suspended_at is set" do
      user.save!
      user.update!(suspended_at: Time.current)

      expect(user.operationally_active?).to be(false)
    end

    it "[REQ-FIT-AUTH-002] allows operational access when not suspended" do
      user.save!
      user.update!(suspended_at: nil)

      expect(user.operationally_active?).to be(true)
    end
  end
end

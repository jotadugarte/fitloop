# frozen_string_literal: true

require "rails_helper"

RSpec.describe Feedback, "[REQ-FIT-OPS-001]" do
  def valid_attributes
    {
      feedback_type: "suggestion",
      message: "Me gustaría poder exportar PDF del taller.",
      email: "guest@example.com"
    }
  end

  subject(:feedback) { described_class.new(valid_attributes) }

  describe "valid submission [REQ-FIT-OPS-001]" do
    it "[REQ-FIT-OPS-001] is valid with required attributes for an anonymous guest" do
      expect(feedback).to be_valid
    end

    it "[REQ-FIT-OPS-001] persists with required attributes" do
      expect { feedback.save! }.to change(described_class, :count).by(1)
    end
  end

  describe "message [REQ-FIT-OPS-001]" do
    it "[REQ-FIT-OPS-001] requires message" do
      feedback.message = nil

      expect(feedback).not_to be_valid
      expect(feedback.errors).to be_of_kind(:message, :blank)
    end

    it "[REQ-FIT-OPS-001] rejects messages shorter than 5 characters" do
      feedback.message = "hola"

      expect(feedback).not_to be_valid
      expect(feedback.errors[:message]).to be_present
    end

    it "[REQ-FIT-OPS-001] rejects messages longer than 5000 characters" do
      feedback.message = "a" * 5001

      expect(feedback).not_to be_valid
      expect(feedback.errors[:message]).to be_present
    end
  end

  describe "feedback_type [REQ-FIT-OPS-001]" do
    it "[REQ-FIT-OPS-001] requires feedback_type" do
      feedback.feedback_type = nil

      expect(feedback).not_to be_valid
      expect(feedback.errors[:feedback_type]).to be_present
    end

    it "[REQ-FIT-OPS-001] rejects invalid feedback_type values" do
      feedback.feedback_type = "invalid"

      expect(feedback).not_to be_valid
      expect(feedback.errors[:feedback_type]).to be_present
    end

    it "[REQ-FIT-OPS-001] accepts suggestion, bug, and other" do
      %w[suggestion bug other].each do |feedback_type|
        record = described_class.new(valid_attributes.merge(feedback_type: feedback_type))

        expect(record).to be_valid
      end
    end
  end

  describe "status [REQ-FIT-OPS-001]" do
    it "[REQ-FIT-OPS-001] defaults to pending" do
      expect(described_class.new.status).to eq("pending")
    end

    it "[REQ-FIT-OPS-001] rejects invalid status values" do
      feedback.status = "invalid"

      expect(feedback).not_to be_valid
      expect(feedback.errors[:status]).to be_present
    end

    it "[REQ-FIT-OPS-001] accepts pending, reviewed, and archived" do
      %w[pending reviewed archived].each do |status|
        record = described_class.new(valid_attributes.merge(status: status))

        expect(record).to be_valid
      end
    end
  end

  describe "email [REQ-FIT-OPS-001]" do
    it "[REQ-FIT-OPS-001] requires email when user is absent" do
      feedback.email = nil

      expect(feedback).not_to be_valid
      expect(feedback.errors[:email]).to be_present
    end

    it "[REQ-FIT-OPS-001] validates email format when present" do
      feedback.email = "not-an-email"

      expect(feedback).not_to be_valid
      expect(feedback.errors[:email]).to be_present
    end

    it "[REQ-FIT-OPS-001] allows authenticated user without email" do
      user = create_billing_user!
      authenticated = described_class.new(
        valid_attributes.merge(user: user, email: nil)
      )

      expect(authenticated).to be_valid
    end
  end

  describe "associations [REQ-FIT-OPS-001]" do
    it "[REQ-FIT-OPS-001] optionally belongs to user" do
      association = described_class.reflect_on_association(:user)

      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be(true)
    end
  end

  describe "submitter_email [REQ-FIT-OPS-001]" do
    it "[REQ-FIT-OPS-001] prefers the authenticated user email" do
      user = create_billing_user!(email: "member@example.com")
      record = described_class.new(
        user: user,
        feedback_type: "bug",
        message: "Preview roto en Safari."
      )

      expect(record.submitter_email).to eq("member@example.com")
    end
  end

  describe ".build_from_params [REQ-FIT-OPS-001]" do
    it "[REQ-FIT-OPS-001] ignores guest metadata for authenticated users" do
      user = create_billing_user!
      guest_context = Feedback::GuestContext.new(ip: "1.1.1.1", user_agent: "RSpec")

      record = described_class.build_from_params(
        params: { feedback_type: "other", message: "Comentario autenticado." },
        user: user,
        guest_context: guest_context
      )

      expect(record.email).to be_nil
      expect(record.guest_metadata).to eq({})
    end

    it "[REQ-FIT-OPS-001] raises when preconditions fail" do
      expect { described_class.precondition!(false) }.to raise_error(ArgumentError, /precondition/)
      expect { described_class.postcondition!(false) }.to raise_error(ArgumentError, /postcondition/)
    end
  end
end
